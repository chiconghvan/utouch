//
//  Util.m
//  zxtouch
//
//  Created by Jason on 2021/1/16.
//
#import "Util.h"

@implementation Util


+ (void)showAlertBoxWithOneOption:(UIViewController*)vc title:(NSString*)aTitle message:(NSString*)aMessage buttonString:(NSString*)aBts
{
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:aTitle
                                                                   message:aMessage
                                   preferredStyle:UIAlertControllerStyleAlert];
     
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:aBts style:UIAlertActionStyleDefault
       handler:^(UIAlertAction * action) {}];
     
    [alert addAction:defaultAction];
    [vc presentViewController:alert animated:YES completion:nil];
}

+ (void)showRunScriptErrorToast:(UIViewController*)vc
{
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!vc.viewIfLoaded) return;

        static NSInteger toastTag = 0x5A585445;
        UIView *oldToast = [vc.view viewWithTag:toastTag];
        [oldToast removeFromSuperview];

        UILabel *toast = [[UILabel alloc] init];
        toast.tag = toastTag;
        toast.translatesAutoresizingMaskIntoConstraints = NO;
        toast.text = @"Run script error";
        toast.textColor = UIColor.whiteColor;
        toast.backgroundColor = UIColor.redColor;
        toast.textAlignment = NSTextAlignmentCenter;
        toast.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        toast.layer.cornerRadius = 8.0;
        toast.clipsToBounds = YES;
        toast.alpha = 0.0;

        [vc.view addSubview:toast];
        UILayoutGuide *safeArea = vc.view.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [toast.centerXAnchor constraintEqualToAnchor:vc.view.centerXAnchor],
            [toast.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor constant:-20.0],
            [toast.leadingAnchor constraintGreaterThanOrEqualToAnchor:vc.view.leadingAnchor constant:20.0],
            [toast.trailingAnchor constraintLessThanOrEqualToAnchor:vc.view.trailingAnchor constant:-20.0],
            [toast.widthAnchor constraintLessThanOrEqualToConstant:280.0],
            [toast.heightAnchor constraintGreaterThanOrEqualToConstant:44.0]
        ]];

        [UIView animateWithDuration:0.2 animations:^{
            toast.alpha = 1.0;
        } completion:^(BOOL finished) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                if (toast.superview) {
                    [UIView animateWithDuration:0.2 animations:^{
                        toast.alpha = 0.0;
                    } completion:^(BOOL finished) {
                        [toast removeFromSuperview];
                    }];
                }
            });
        }];
    });
}




@end
