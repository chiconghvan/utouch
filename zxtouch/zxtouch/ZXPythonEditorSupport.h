#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ZXPythonEditorSupport : NSObject

+ (NSString *)formatSource:(NSString *)source;
+ (NSString *)indentationForNewLineAfterText:(NSString *)text cursorLocation:(NSUInteger)cursorLocation;
+ (NSArray<NSDictionary *> *)tokensForSource:(NSString *)source;
+ (NSArray<NSDictionary *> *)completionsForSource:(NSString *)source cursorLocation:(NSUInteger)cursorLocation;
+
@end

NS_ASSUME_NONNULL_END
