#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXPythonEditorSupport : NSObject

+ (NSString *)formatSource:(NSString *)source;
+ (NSString *)indentationForNewLineAfterText:(NSString *)text cursorLocation:(NSUInteger)cursorLocation;
+ (NSArray<NSDictionary *> *)tokensForSource:(NSString *)source;
+ (NSArray<NSDictionary *> *)completionsForSource:(NSString *)source cursorLocation:(NSUInteger)cursorLocation;

/// Lines the editor displays for `source` (a trailing newline opens one more).
+ (NSUInteger)lineCountForSource:(NSString *)source;

/// Parse the JSON report written by `zxtouch.checker` into normalized
/// diagnostics: `{ code, severity, line, column, endLine, endColumn, message }`.
+ (NSArray<NSDictionary *> *)diagnosticsFromReportData:(NSData *)data;

/// Convert 1-based line/column diagnostics into `NSRange`s within `source`.
/// Each result is `{ range, severity, message, code }`, ready for underlining.
+ (NSArray<NSDictionary *> *)rangesForDiagnostics:(NSArray<NSDictionary *> *)diagnostics inSource:(NSString *)source;

@end

NS_ASSUME_NONNULL_END
