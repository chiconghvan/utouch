#import <XCTest/XCTest.h>
#import "../zxtouch/ZXPythonEditorSupport.h"

@interface ZXPythonEditorSupportTests : XCTestCase
@end

@implementation ZXPythonEditorSupportTests

- (void)testNewLineIndentationAfterBlock {
    NSString *source = @"if ready:";
    XCTAssertEqualObjects([ZXPythonEditorSupport indentationForNewLineAfterText:source cursorLocation:source.length], @"    ");
}

- (void)testNewLineIndentationPreservesNestedLevel {
    NSString *source = @"if ready:\n    tap(1, 2)";
    XCTAssertEqualObjects([ZXPythonEditorSupport indentationForNewLineAfterText:source cursorLocation:source.length], @"    ");
}

- (void)testFormatterNormalizesIndentationAndDedentsElse {
    NSString *source = @"if ready:\n\ttap(1, 2)\n\telse:  \n\t\tlog('no')  ";
    NSString *expected = @"if ready:\n    tap(1, 2)\nelse:\n        log('no')";
    XCTAssertEqualObjects([ZXPythonEditorSupport formatSource:source], expected);
}

- (void)testFormatterDoesNotChangeTripleQuotedString {
    NSString *source = @"message = \"\"\"first:\n  second\n\"\"\"\nif ok:";
    XCTAssertEqualObjects([ZXPythonEditorSupport formatSource:source], source);
}

- (void)testPythonTokensKeepKeywordsOutOfStringsAndComments {
    NSString *source = @"if tap(10, 20): # if comment\n    log(\"return\")";
    NSArray *tokens = [ZXPythonEditorSupport tokensForSource:source];
    NSMutableArray *types = [NSMutableArray array];
    for (NSDictionary *token in tokens) [types addObject:token[@"type"]];
    XCTAssertTrue([types containsObject:@"keyword"]);
    XCTAssertTrue([types containsObject:@"call"]);
    XCTAssertTrue([types containsObject:@"comment"]);
    XCTAssertTrue([types containsObject:@"string"]);
}

- (void)testCompletionsIncludeSignatureAndOutputType {
    NSArray *items = [ZXPythonEditorSupport completionsForSource:@"ta" cursorLocation:2];
    NSDictionary *tap = nil;
    for (NSDictionary *item in items) {
        if ([item[@"name"] isEqualToString:@"tap"]) tap = item;
    }
    XCTAssertNotNil(tap);
    XCTAssertTrue([tap[@"signature"] length] > 0);
    XCTAssertTrue([tap[@"outputType"] length] > 0);
    XCTAssertEqualObjects(tap[@"insertText"], @"tap()");
}

- (void)testCompletionsIncludeLocalSymbols {
    NSString *source = @"def login(username):\n    token = username\n    return token\n\n";
    NSArray *items = [ZXPythonEditorSupport completionsForSource:source cursorLocation:source.length];
    NSMutableSet *names = [NSMutableSet set];
    for (NSDictionary *item in items) [names addObject:item[@"name"]];
    XCTAssertTrue([names containsObject:@"login"]);
    XCTAssertTrue([names containsObject:@"token"]);
}

- (void)testNoCompletionsInsideStringOrComment {
    NSString *stringSource = @"\"ta";
    NSString *commentSource = @"# ta";
    XCTAssertEqual([ZXPythonEditorSupport completionsForSource:stringSource cursorLocation:stringSource.length].count, 0U);
    XCTAssertEqual([ZXPythonEditorSupport completionsForSource:commentSource cursorLocation:commentSource.length].count, 0U);
}

- (void)testDiagnosticsParseDefaultsAndSkipsGarbage {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{
        @"ok": @NO,
        @"diagnostics": @[
            @{ @"severity": @"error", @"code": @"E200", @"line": @2, @"column": @3,
               @"endLine": @2, @"endColumn": @7, @"message": @"unknown" },
            @{ @"line": @1, @"message": @"no severity" },
        ],
    } options:0];
    NSArray *items = [ZXPythonEditorSupport diagnosticsFromReportData:data];
    XCTAssertEqual(items.count, 2U);
    XCTAssertEqualObjects(items[0][@"code"], @"E200");
    XCTAssertEqualObjects(items[0][@"severity"], @"error");
    XCTAssertEqualObjects(items[1][@"severity"], @"error");
    XCTAssertEqualObjects(items[1][@"endLine"], @1);
    XCTAssertEqualObjects(items[1][@"endColumn"], @1);
}

- (void)testDiagnosticsParseHandlesEmptyAndInvalidData {
    XCTAssertEqual([ZXPythonEditorSupport diagnosticsFromReportData:[NSData data]].count, 0U);
    XCTAssertEqual([ZXPythonEditorSupport diagnosticsFromReportData:[@"not json" dataUsingEncoding:NSUTF8StringEncoding]].count, 0U);
    XCTAssertEqual([ZXPythonEditorSupport diagnosticsFromReportData:
                    [NSJSONSerialization dataWithJSONObject:@{ @"ok": @YES } options:0]].count, 0U);
}

- (void)testRangesOnFirstLine {
    NSString *source = @"taap(1, 2)\n";
    NSArray *items = [ZXPythonEditorSupport rangesForDiagnostics:
                      @[ @{ @"line": @1, @"column": @1, @"endLine": @1, @"endColumn": @5, @"severity": @"error", @"message": @"m" } ]
                                                        inSource:source];
    XCTAssertEqual(items.count, 1U);
    NSRange range = [items[0][@"range"] rangeValue];
    XCTAssertEqual(range.location, 0U);
    XCTAssertEqual(range.length, 4U);
    XCTAssertEqualObjects([source substringWithRange:range], @"taap");
    XCTAssertEqualObjects(items[0][@"severity"], @"error");
}

- (void)testRangesOnLaterLine {
    NSString *source = @"ok\nbad(1)\n";
    NSArray *items = [ZXPythonEditorSupport rangesForDiagnostics:
                      @[ @{ @"line": @2, @"column": @1, @"endLine": @2, @"endColumn": @4 } ]
                                                        inSource:source];
    NSRange range = [items[0][@"range"] rangeValue];
    XCTAssertEqualObjects([source substringWithRange:range], @"bad");
    XCTAssertEqualObjects(items[0][@"severity"], @"error");
}

- (void)testRangesAccountForNonASCIILines {
    NSString *source = @"log('xin chào')\ntaap(1, 2)\n";
    NSArray *items = [ZXPythonEditorSupport rangesForDiagnostics:
                      @[ @{ @"line": @2, @"column": @1, @"endLine": @2, @"endColumn": @5 } ]
                                                        inSource:source];
    NSRange range = [items[0][@"range"] rangeValue];
    XCTAssertEqualObjects([source substringWithRange:range], @"taap");
}

- (void)testRangesClampOutOfBoundsColumnsAndLines {
    NSString *source = @"tap(1)\n";
    NSArray *items = [ZXPythonEditorSupport rangesForDiagnostics:
                      @[ @{ @"line": @9, @"column": @1, @"endLine": @9, @"endColumn": @4 },
                         @{ @"line": @1, @"column": @99, @"endLine": @1, @"endColumn": @120 } ]
                                                        inSource:source];
    // Out-of-range line is dropped; an oversized column clamps to the line end.
    XCTAssertEqual(items.count, 1U);
    NSRange range = [items[0][@"range"] rangeValue];
    XCTAssertTrue(NSMaxRange(range) <= source.length);
    XCTAssertTrue(range.length > 0);
}

- (void)testRangesIgnoreMalformedEntries {
    XCTAssertEqual([ZXPythonEditorSupport rangesForDiagnostics:@[ @"nope" ] inSource:@"tap(1)"].count, 0U);
}

@end
