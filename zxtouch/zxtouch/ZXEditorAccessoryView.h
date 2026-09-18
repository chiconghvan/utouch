//
//  ZXEditorAccessoryView.h
//  zxtouch
//
//  Horizontally scrollable extra-keys pane. The owning view controller docks
//  it at the bottom of the editor and slides it above the keyboard.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol ZXEditorAccessoryViewDelegate <NSObject>
- (void)editorAccessoryView:(UIView *)view
             didActivateKey:(NSString *)identifier
                   repeated:(BOOL)repeated;
@end

@interface ZXEditorAccessoryView : UIView

@property (nonatomic, weak, nullable) id<ZXEditorAccessoryViewDelegate> delegate;

- (void)configureWithIdentifiers:(NSArray<NSString *> *)identifiers;

@end

NS_ASSUME_NONNULL_END
