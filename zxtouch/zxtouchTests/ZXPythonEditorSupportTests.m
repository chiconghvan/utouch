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

@end
