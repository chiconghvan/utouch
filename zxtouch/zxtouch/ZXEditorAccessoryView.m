//
//  ZXEditorAccessoryView.m
//  zxtouch
//

#import "ZXEditorAccessoryView.h"
#import "ZXEditorAccessoryKeys.h"
#import <objc/runtime.h>

@interface ZXEditorAccessoryView ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *stackView;
// Repeat state for long-pressed navigation/deletion keys.
@property (nonatomic, copy, nullable) NSString *repeatIdentifier;
@property (nonatomic, strong, nullable) NSTimer *repeatTimer;
@end

@implementation ZXEditorAccessoryView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor systemBackgroundColor];

        UIView *hairline = [[UIView alloc] init];
        hairline.translatesAutoresizingMaskIntoConstraints = NO;
        hairline.backgroundColor = [UIColor separatorColor];
        [self addSubview:hairline];

        _scrollView = [[UIScrollView alloc] init];
        _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
        _scrollView.showsHorizontalScrollIndicator = NO;
        _scrollView.showsVerticalScrollIndicator = NO;
        [self addSubview:_scrollView];

        _stackView = [[UIStackView alloc] init];
        _stackView.translatesAutoresizingMaskIntoConstraints = NO;
        _stackView.axis = UILayoutConstraintAxisHorizontal;
        _stackView.spacing = 8.0;
        _stackView.alignment = UIStackViewAlignmentCenter;
        [_scrollView addSubview:_stackView];

        [NSLayoutConstraint activateConstraints:@[
            [hairline.topAnchor constraintEqualToAnchor:self.topAnchor],
            [hairline.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [hairline.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [hairline.heightAnchor constraintEqualToConstant:1.0 / MAX(UIScreen.mainScreen.scale, 1.0)],

            [_scrollView.topAnchor constraintEqualToAnchor:self.topAnchor constant:1.0],
            [_scrollView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
            [_scrollView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
            [_scrollView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],

            [_stackView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
            [_stackView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
            [_stackView.leadingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.leadingAnchor constant:8.0],
            [_stackView.trailingAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.trailingAnchor constant:-8.0],
            [_stackView.heightAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.heightAnchor],
        ]];
    }
    return self;
}

- (void)configureWithIdentifiers:(NSArray<NSString *> *)identifiers {
    [self stopRepeating];
    for (UIView *subview in self.stackView.arrangedSubviews) {
        [self.stackView removeArrangedSubview:subview];
        [subview removeFromSuperview];
    }
    for (NSString *identifier in identifiers) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.translatesAutoresizingMaskIntoConstraints = NO;
        button.backgroundColor = [UIColor secondarySystemBackgroundColor];
        button.layer.cornerRadius = 8.0;
        button.layer.masksToBounds = YES;
        button.contentEdgeInsets = UIEdgeInsetsMake(6.0, 12.0, 6.0, 12.0);
        button.titleLabel.font = [UIFont monospacedSystemFontOfSize:16.0 weight:UIFontWeightMedium];
        [button setTitle:[ZXEditorAccessoryKeys titleForIdentifier:identifier]
                forState:UIControlStateNormal];
        button.accessibilityLabel = [ZXEditorAccessoryKeys titleForIdentifier:identifier];
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:44.0].active = YES;
        [button.heightAnchor constraintEqualToConstant:34.0].active = YES;
        objc_setAssociatedObject(button, @selector(handleKeyTap:), [identifier copy], OBJC_ASSOCIATION_COPY_NONATOMIC);
        [button addTarget:self action:@selector(handleKeyTap:) forControlEvents:UIControlEventTouchUpInside];
        if ([ZXEditorAccessoryKeys isRepeatableIdentifier:identifier]) {
            UILongPressGestureRecognizer *hold = [[UILongPressGestureRecognizer alloc]
                initWithTarget:self action:@selector(handleKeyHold:)];
            hold.minimumPressDuration = 0.4;
            [button addGestureRecognizer:hold];
        }
        [self.stackView addArrangedSubview:button];
    }
}

#pragma mark - Events

- (nullable NSString *)identifierForButton:(UIButton *)button {
    return objc_getAssociatedObject(button, @selector(handleKeyTap:));
}

- (void)handleKeyTap:(UIButton *)button {
    // A tap right after a long-press repeat would double-fire; the hold
    // handler suppresses the tap in that case via repeatIdentifier cleanup.
    if (self.repeatIdentifier) return;
    NSString *identifier = [self identifierForButton:button];
    if (!identifier) return;
    [self.delegate editorAccessoryView:self didActivateKey:identifier repeated:NO];
}

- (void)handleKeyHold:(UILongPressGestureRecognizer *)recognizer {
    UIButton *button = (UIButton *)recognizer.view;
    NSString *identifier = button ? [self identifierForButton:button] : nil;
    if (!identifier) return;
    if (recognizer.state == UIGestureRecognizerStateBegan) {
        self.repeatIdentifier = identifier;
        [self.delegate editorAccessoryView:self didActivateKey:identifier repeated:YES];
        [self.repeatTimer invalidate];
        self.repeatTimer = [NSTimer scheduledTimerWithTimeInterval:0.07
                                                            target:self
                                                          selector:@selector(fireRepeat:)
                                                          userInfo:nil
                                                           repeats:YES];
    } else if (recognizer.state == UIGestureRecognizerStateEnded
            || recognizer.state == UIGestureRecognizerStateCancelled
            || recognizer.state == UIGestureRecognizerStateFailed) {
        // Delay clearing so the companion touchUpInside from the same finger
        // does not emit one extra non-repeated activation.
        NSString *finished = [identifier copy];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if ([self.repeatIdentifier isEqualToString:finished]) self.repeatIdentifier = nil;
        });
        [self stopRepeating];
    }
}

- (void)fireRepeat:(NSTimer *)timer {
    if (!self.repeatIdentifier) {
        [self stopRepeating];
        return;
    }
    [self.delegate editorAccessoryView:self didActivateKey:self.repeatIdentifier repeated:YES];
}

- (void)stopRepeating {
    [self.repeatTimer invalidate];
    self.repeatTimer = nil;
}

- (void)removeFromSuperview {
    [self stopRepeating];
    [super removeFromSuperview];
}

@end
