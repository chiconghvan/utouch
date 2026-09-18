#import "ScriptEditorViewController.h"
#import "ZXPythonEditorSupport.h"
#import "Socket.h"
#import "Config.h"
#import "ConfigManager.h"
#import "ZXEditorAccessoryKeys.h"
#import "ZXEditorAccessoryView.h"

static const CGFloat ZXLineNumberHorizontalPadding = 6.0;
static const CGFloat ZXLineNumberTextGap = 6.0;

/// Editor font size chosen in Settings, clamped to the range the slider offers.
static CGFloat ZXEditorFontSize(void)
{
    ConfigManager *config = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];
    id value = [config getValueFromKey:ZX_EDITOR_FONT_SIZE_KEY];
    CGFloat size = value ? [value doubleValue] : ZX_EDITOR_FONT_SIZE_DEFAULT;
    if (size < ZX_EDITOR_FONT_SIZE_MIN || size > ZX_EDITOR_FONT_SIZE_MAX) size = ZX_EDITOR_FONT_SIZE_DEFAULT;
    return size;
}

static UIFont *ZXEditorFont(void)
{
    return [UIFont monospacedSystemFontOfSize:ZXEditorFontSize() weight:UIFontWeightRegular];
}

/// Gutter drawn inside the text view, so it scrolls with the content.
/// Numbers come from the layout manager's line fragments: a wrapped
/// continuation belongs to the same logical line and is not numbered twice.
@interface ZXLineNumberView : UIView
@property (nonatomic, weak) UITextView *textView;
@property (nonatomic, strong) UIFont *numberFont;
@end

@implementation ZXLineNumberView

+ (NSUInteger)newlineCount:(NSString *)text from:(NSUInteger)location to:(NSUInteger)end
{
    NSUInteger count = 0;
    NSUInteger limit = MIN(end, text.length);
    for (NSUInteger index = MIN(location, limit); index < limit; index++) {
        if ([text characterAtIndex:index] == '\n') count++;
    }
    return count;
}

- (void)drawNumber:(NSUInteger)number atY:(CGFloat)y attributes:(NSDictionary *)attributes rightEdge:(CGFloat)rightEdge
{
    NSString *label = [NSString stringWithFormat:@"%lu", (unsigned long)number];
    CGSize size = [label sizeWithAttributes:attributes];
    [label drawAtPoint:CGPointMake(rightEdge - size.width, y) withAttributes:attributes];
}

- (void)drawRect:(CGRect)rect
{
    UITextView *textView = self.textView;
    if (!textView) return;

    CGFloat width = CGRectGetWidth(self.bounds);
    CGFloat height = CGRectGetHeight(self.bounds);
    [[UIColor secondarySystemBackgroundColor] setFill];
    UIRectFill(rect);
    CGFloat hairline = 1.0 / MAX(UIScreen.mainScreen.scale, 1.0);
    [[UIColor separatorColor] setFill];
    UIRectFill(CGRectMake(width - hairline, 0, hairline, height));

    UIFont *font = self.numberFont ?: textView.font;
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: [UIColor secondaryLabelColor],
    };
    CGFloat rightEdge = width - ZXLineNumberHorizontalPadding;
    UIEdgeInsets inset = textView.textContainerInset;
    NSString *text = textView.text ?: @"";

    if (text.length == 0) {
        [self drawNumber:1 atY:inset.top attributes:attributes rightEdge:rightEdge];
        return;
    }

    NSLayoutManager *layoutManager = textView.layoutManager;
    NSUInteger glyphCount = layoutManager.numberOfGlyphs;
    __block NSUInteger drawnLine = 0;
    __block NSUInteger logicalLine = 1;
    __block NSUInteger scanned = 0;
    __block CGFloat lastY = inset.top;
    __block CGFloat lastHeight = font.lineHeight;

    if (glyphCount > 0) {
        [layoutManager enumerateLineFragmentsForGlyphRange:NSMakeRange(0, glyphCount)
            usingBlock:^(CGRect fragmentRect, CGRect usedRect, NSTextContainer *textContainer, NSRange glyphRange, BOOL *stop) {
                NSUInteger charIndex = [layoutManager characterIndexForGlyphAtIndex:glyphRange.location];
                if (charIndex > scanned) {
                    logicalLine += [ZXLineNumberView newlineCount:text from:scanned to:charIndex];
                    scanned = charIndex;
                }
                lastY = CGRectGetMinY(fragmentRect) + inset.top;
                lastHeight = CGRectGetHeight(fragmentRect);
                if (logicalLine == drawnLine) return; // wrapped continuation
                drawnLine = logicalLine;
                // Only visible rows are painted; a long script must not redraw
                // every number for each scroll tile.
                if (!CGRectIntersectsRect(CGRectMake(0, lastY, width, MAX(lastHeight, 1.0)), rect)) return;
                [self drawNumber:logicalLine atY:lastY attributes:attributes rightEdge:rightEdge];
            }];
    }

    // A trailing newline opens one more line, which has no glyph of its own.
    if ([text characterAtIndex:text.length - 1] == '\n') {
        CGFloat trailingY = lastY + lastHeight;
        if (CGRectIntersectsRect(CGRectMake(0, trailingY, width, MAX(lastHeight, 1.0)), rect)) {
            [self drawNumber:logicalLine + 1 atY:trailingY attributes:attributes rightEdge:rightEdge];
        }
    }
}

@end

@interface ScriptEditorViewController () <UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate, ZXEditorAccessoryViewDelegate>
- (void)refreshBarButtons;
- (void)checkScript;
- (void)runValidation;
- (NSString *)validationFilePath;
- (NSArray<NSDictionary *> *)validateSource:(NSString *)source;
- (void)applyDiagnosticsToAttributedString:(NSMutableAttributedString *)attributed source:(NSString *)source;
- (NSInteger)errorCount;
- (void)updateValidationStatus;
- (void)showProblems;
- (void)writeFile;
- (void)finishPendingSave;
- (void)updateLineNumbers;
- (void)applyEditorFontSize;
- (void)configureToast;
- (void)showEditorToast:(NSString *)message isError:(BOOL)isError;
- (void)hideEditorToast;
- (void)handleToastTap;
- (void)handleEditorTap:(UITapGestureRecognizer *)recognizer;
- (void)keyboardWillChangeFrame:(NSNotification *)note;
- (void)configureExtraKeysBar;
- (void)reloadExtraKeysBar;
- (CGFloat)extraKeysVisibleHeight;
- (void)handleExtraKey:(NSString *)identifier repeated:(BOOL)repeated;
- (void)extraKeysMoveLeft;
- (void)extraKeysMoveRight;
- (void)extraKeysMoveUp;
- (void)extraKeysMoveDown;
- (void)extraKeysMoveHome;
- (void)extraKeysMoveEnd;
- (void)extraKeysDedentLines;
- (void)extraKeysToggleComment;
- (void)extraKeysDeleteLine;
- (NSRange)extraKeysSelectedLineBlock:(NSString *)text;
@end

@implementation ScriptEditorViewController
{
    NSString *currentFilePath;
    BOOL isSaveButtonShown;
    BOOL isApplyingHighlight;
    BOOL isApplyingEdit;
    UITableView *completionTableView;
    NSArray<NSDictionary *> *completionItems;
    NSRange completionRange;
    UIBarButtonItem *saveButton;
    UIBarButtonItem *problemsButton;
    UIBarButtonItem *checkButton;
    BOOL saveAfterValidation;
    NSArray<NSDictionary *> *diagnostics;
    NSString *diagnosticsSource;
    NSUInteger validationGeneration;
    ZXLineNumberView *lineNumberView;
    UIView *toastView;
    UILabel *toastLabel;
    NSLayoutConstraint *toastBottomConstraint;
    NSTimer *toastTimer;
    NSString *lastToastMessage;
    CGFloat keyboardBottomInset;
    BOOL toastHasProblems;
    ZXEditorAccessoryView *extraKeysBar;
    NSLayoutConstraint *extraKeysBottomConstraint;
    NSLayoutConstraint *extraKeysHeightConstraint;
    NSArray<NSString *> *extraKeysIdentifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *content = [NSString stringWithContentsOfFile:currentFilePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL] ?: @"";
    _textInput.text = content;
    _textInput.font = ZXEditorFont();
    _textInput.autocorrectionType = UITextAutocorrectionTypeNo;
    _textInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textInput.smartDashesType = UITextSmartDashesTypeNo;
    _textInput.smartQuotesType = UITextSmartQuotesTypeNo;
    _textInput.delegate = self;
    _textInput.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    // Gutter lives inside the text view so it scrolls with the content.
    lineNumberView = [[ZXLineNumberView alloc] initWithFrame:CGRectZero];
    lineNumberView.textView = _textInput;
    lineNumberView.numberFont = _textInput.font;
    lineNumberView.userInteractionEnabled = NO;
    [_textInput addSubview:lineNumberView];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(applyEditorFontSize)
                                                  name:ZX_EDITOR_FONT_SIZE_CHANGED_NOTIFICATION
                                                object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                              selector:@selector(reloadExtraKeysBar)
                                                  name:ZX_EDITOR_EXTRA_KEYS_CHANGED_NOTIFICATION
                                                object:nil];
    // The text view is pinned to the safe area, which the keyboard does not
    // change, so the bottom inset has to be maintained by hand.
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [self configureCompletionTable];
    [self configureToast];
    [self configureExtraKeysBar];
    [self refreshBarButtons];
    [self applySyntaxHighlightingPreservingSelection:NO];
    isSaveButtonShown = NO;
    [self updateLineNumbers];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self hideEditorToast];
}

- (void)setFile:(NSString *)file {
    currentFilePath = [file stringByStandardizingPath];
}

- (BOOL)isPythonFile {
    return [[[currentFilePath pathExtension] lowercaseString] isEqualToString:@"py"];
}

- (void)configureCompletionTable {
    completionTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    completionTableView.hidden = YES;
    completionTableView.dataSource = self;
    completionTableView.delegate = self;
    completionTableView.layer.borderWidth = 1.0;
    completionTableView.layer.borderColor = [UIColor separatorColor].CGColor;
    completionTableView.layer.cornerRadius = 6.0;
    completionTableView.clipsToBounds = YES;
    completionTableView.rowHeight = 54.0;
    completionTableView.backgroundColor = [UIColor systemBackgroundColor];
    [self.view addSubview:completionTableView];

    UITapGestureRecognizer *dismissTap = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                action:@selector(handleEditorTap:)];
    dismissTap.cancelsTouchesInView = NO;
    dismissTap.delegate = self;
    [self.view addGestureRecognizer:dismissTap];
}

- (void)handleEditorTap:(UITapGestureRecognizer *)recognizer {
    if (!completionTableView.hidden) [self hideCompletions];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (gestureRecognizer.view != self.view) return YES;
    return ![touch.view isDescendantOfView:completionTableView];
}

- (void)refreshBarButtons {
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
    if ([self isPythonFile]) {
        if (!checkButton) {
            checkButton = [[UIBarButtonItem alloc] initWithTitle:@"Check"
                                                           style:UIBarButtonItemStylePlain
                                                          target:self
                                                          action:@selector(checkScript)];
        }
        [items addObject:checkButton];
    }
    if (diagnostics.count > 0) {
        if (!problemsButton) {
            problemsButton = [[UIBarButtonItem alloc] initWithTitle:@"Problems"
                                                              style:UIBarButtonItemStylePlain
                                                             target:self
                                                             action:@selector(showProblems)];
        }
        [items addObject:problemsButton];
    }
    if (isSaveButtonShown) {
        if (!saveButton) {
            saveButton = [[UIBarButtonItem alloc] initWithTitle:@"Save"
                                                          style:UIBarButtonItemStylePlain
                                                         target:self
                                                         action:@selector(saveFile)];
        }
        [items addObject:saveButton];
    }
    self.navigationItem.rightBarButtonItems = items.count ? items : nil;
}

- (void)showSaveButton {
    if (!isSaveButtonShown) {
        isSaveButtonShown = YES;
        [self refreshBarButtons];
    }
}

- (void)hideSaveButton {
    if (isSaveButtonShown) {
        isSaveButtonShown = NO;
        [self refreshBarButtons];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self updateLineNumbers];
    if (!completionTableView.hidden) [self positionCompletionTable];
}

- (void)textViewDidChange:(UITextView *)textView {
    if (isApplyingHighlight || isApplyingEdit) return;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self updateCompletions];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if (![self isPythonFile] || isApplyingEdit) return YES;
    if ([text isEqualToString:@"\n"] && range.length == 0) {
        NSString *indentation = [ZXPythonEditorSupport indentationForNewLineAfterText:textView.text
                                                                          cursorLocation:range.location];
        isApplyingEdit = YES;
        UITextPosition *start = [textView positionFromPosition:textView.beginningOfDocument offset:range.location];
        UITextRange *textRange = [textView textRangeFromPosition:start toPosition:start];
        [textView replaceRange:textRange withText:[NSString stringWithFormat:@"\n%@", indentation]];
        isApplyingEdit = NO;
        [self applySyntaxHighlightingPreservingSelection:YES];
        [self showSaveButton];
        [self updateCompletions];
        return NO;
    }
    if ([text isEqualToString:@"\t"]) {
        NSString *spaces = [@"" stringByPaddingToLength:ZX_EDITOR_INDENT_WIDTH
                                             withString:@" "
                                        startingAtIndex:0];
        isApplyingEdit = YES;
        UITextPosition *start = [textView positionFromPosition:textView.beginningOfDocument offset:range.location];
        UITextPosition *end = [textView positionFromPosition:start offset:range.length];
        UITextRange *textRange = [textView textRangeFromPosition:start toPosition:end];
        [textView replaceRange:textRange withText:spaces];
        isApplyingEdit = NO;
        [self applySyntaxHighlightingPreservingSelection:YES];
        [self showSaveButton];
        [self updateCompletions];
        return NO;
    }
    if (text.length > 1 && [text containsString:@"\n"]) {
        NSString *formatted = [ZXPythonEditorSupport formatSource:text];
        if (![formatted isEqualToString:text]) {
            isApplyingEdit = YES;
            UITextPosition *start = [textView positionFromPosition:textView.beginningOfDocument offset:range.location];
            UITextPosition *end = [textView positionFromPosition:start offset:range.length];
            UITextRange *textRange = [textView textRangeFromPosition:start toPosition:end];
            [textView replaceRange:textRange withText:formatted];
            isApplyingEdit = NO;
            [self applySyntaxHighlightingPreservingSelection:YES];
            [self showSaveButton];
            [self updateCompletions];
            return NO;
        }
    }
    return YES;
}

- (void)applyColor:(UIColor *)color pattern:(NSString *)pattern options:(NSRegularExpressionOptions)options inString:(NSString *)content attributedString:(NSMutableAttributedString *)attributed {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:&error];
    if (error) return;

    NSRange fullRange = NSMakeRange(0, content.length);
    [regex enumerateMatchesInString:content options:0 range:fullRange usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        if (result.range.location != NSNotFound && NSMaxRange(result.range) <= attributed.length) {
            [attributed addAttribute:NSForegroundColorAttributeName value:color range:result.range];
        }
    }];
}

- (void)applyPythonTokens:(NSArray<NSDictionary *> *)tokens toAttributedString:(NSMutableAttributedString *)attributed {
    UIColor *keywordColor = [UIColor systemPurpleColor];
    UIColor *stringColor = [UIColor systemRedColor];
    UIColor *commentColor = [UIColor systemGreenColor];
    UIColor *numberColor = [UIColor systemOrangeColor];
    UIColor *callColor = [UIColor systemBlueColor];
    for (NSDictionary *token in tokens) {
        NSRange range = [token[@"range"] rangeValue];
        NSString *type = token[@"type"];
        UIColor *color = nil;
        if ([type isEqualToString:@"keyword"]) color = keywordColor;
        else if ([type isEqualToString:@"string"]) color = stringColor;
        else if ([type isEqualToString:@"comment"]) color = commentColor;
        else if ([type isEqualToString:@"number"]) color = numberColor;
        else if ([type isEqualToString:@"call"]) color = callColor;
        if (color && NSMaxRange(range) <= attributed.length) [attributed addAttribute:NSForegroundColorAttributeName value:color range:range];
    }
}

- (void)applySyntaxHighlightingPreservingSelection:(BOOL)preserveSelection {
    NSString *content = _textInput.text ?: @"";
    NSString *extension = [[currentFilePath pathExtension] lowercaseString];
    NSRange selectedRange = _textInput.selectedRange;
    UIColor *baseColor = UIColor.labelColor ?: UIColor.blackColor;
    UIFont *font = _textInput.font ?: [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    NSMutableAttributedString *highlighted = [[NSMutableAttributedString alloc] initWithString:content attributes:@{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: baseColor
    }];

    if ([extension isEqualToString:@"py"]) {
        [self applyPythonTokens:[ZXPythonEditorSupport tokensForSource:content] toAttributedString:highlighted];
    } else if ([extension isEqualToString:@"raw"]) {
        [self applyColor:[UIColor systemBlueColor] pattern:@"^\\d{2}" options:NSRegularExpressionAnchorsMatchLines inString:content attributedString:highlighted];
        [self applyColor:[UIColor systemOrangeColor] pattern:@"\\b\\d+(\\.\\d+)?\\b" options:0 inString:content attributedString:highlighted];
    } else if ([extension isEqualToString:@"md"] || [extension isEqualToString:@"markdown"]) {
        [self applyColor:[UIColor systemPurpleColor] pattern:@"^#{1,6} .*$" options:NSRegularExpressionAnchorsMatchLines inString:content attributedString:highlighted];
        [self applyColor:[UIColor systemBlueColor] pattern:@"`[^`]+`" options:0 inString:content attributedString:highlighted];
        [self applyColor:[UIColor systemGreenColor] pattern:@"\\[[^\\]]+\\]\\([^\\)]+\\)" options:0 inString:content attributedString:highlighted];
    }

    if ([extension isEqualToString:@"py"]) [self applyDiagnosticsToAttributedString:highlighted source:content];

    isApplyingHighlight = YES;
    _textInput.attributedText = highlighted;
    if (preserveSelection && NSMaxRange(selectedRange) <= _textInput.text.length) _textInput.selectedRange = selectedRange;
    isApplyingHighlight = NO;
    [self updateLineNumbers];
}

- (void)updateCompletions {
    if (![self isPythonFile] || isApplyingEdit || !_textInput.isFirstResponder) {
        [self hideCompletions];
        return;
    }
    NSArray *items = [ZXPythonEditorSupport completionsForSource:_textInput.text cursorLocation:_textInput.selectedRange.location];
    if (items.count == 0) {
        [self hideCompletions];
        return;
    }
    completionItems = items;
    NSString *text = _textInput.text ?: @"";
    NSUInteger cursor = _textInput.selectedRange.location;
    NSUInteger start = cursor;
    while (start > 0) {
        unichar character = [text characterAtIndex:start - 1];
        if (!((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || (character >= '0' && character <= '9') || character == '_' || character == '.')) break;
        start--;
    }
    completionRange = NSMakeRange(start, cursor - start);
    if (completionRange.length == 0) {
        [self hideCompletions];
        return;
    }
    completionTableView.hidden = NO;
    [completionTableView reloadData];
    [self positionCompletionTable];
}

- (void)hideCompletions {
    completionItems = @[];
    completionTableView.hidden = YES;
}

- (void)positionCompletionTable {
    if (completionTableView.hidden) return;
    UITextPosition *caretPosition = _textInput.selectedTextRange.end;
    if (!caretPosition) return;
    CGRect caret = [_textInput caretRectForPosition:caretPosition];
    CGRect caretInView = [_textInput convertRect:caret toView:self.view];
    CGFloat width = MIN(CGRectGetWidth(self.view.bounds) - 24.0, 330.0);
    CGFloat height = MIN(270.0, MAX(54.0, completionItems.count * 54.0));
    CGFloat x = MAX(12.0, MIN(CGRectGetWidth(self.view.bounds) - width - 12.0, CGRectGetMinX(caretInView)));
    CGFloat y = CGRectGetMaxY(caretInView) + 4.0;
    CGFloat availableBottom = CGRectGetHeight(self.view.bounds) - keyboardBottomInset
        - [self extraKeysVisibleHeight] - 12.0;
    if (y + height > availableBottom) y = MAX(12.0, CGRectGetMinY(caretInView) - height - 4.0);
    completionTableView.frame = CGRectMake(x, y, width, height);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return completionItems.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"CompletionCell"];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"CompletionCell"];
    NSDictionary *item = completionItems[indexPath.row];
    cell.textLabel.text = item[@"name"];
    cell.textLabel.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@  → %@", item[@"signature"], item[@"outputType"]];
    cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= completionItems.count) return;
    NSDictionary *item = completionItems[indexPath.row];
    NSString *insertText = item[@"insertText"] ?: item[@"name"];
    NSRange range = completionRange;
    if (NSMaxRange(range) > _textInput.text.length) return;
    isApplyingEdit = YES;
    [_textInput.textStorage replaceCharactersInRange:range withString:insertText];
    NSUInteger cursorLocation = range.location + insertText.length;
    if ([item[@"kind"] isEqualToString:@"function"] && [insertText hasSuffix:@"()"] && insertText.length > 1) cursorLocation--;
    _textInput.selectedRange = NSMakeRange(cursorLocation, 0);
    isApplyingEdit = NO;
    [self hideCompletions];
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
}

#pragma mark - Extra keys pane

// The pane is a separate region docked at the bottom of the editor: the text
// view shrinks to end at the pane's top edge. When the keyboard appears the
// same view slides up with it via extraKeysBottomConstraint (see
// keyboardWillChangeFrame:), so there is only one instance to keep in sync.
- (void)configureExtraKeysBar {
    extraKeysBar = [[ZXEditorAccessoryView alloc] init];
    extraKeysBar.translatesAutoresizingMaskIntoConstraints = NO;
    extraKeysBar.delegate = self;
    [self.view addSubview:extraKeysBar];

    extraKeysBottomConstraint = [extraKeysBar.bottomAnchor
        constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                       constant:-keyboardBottomInset];
    extraKeysHeightConstraint = [extraKeysBar.heightAnchor
        constraintEqualToConstant:ZX_EDITOR_ACCESSORY_BAR_HEIGHT];
    [NSLayoutConstraint activateConstraints:@[
        [extraKeysBar.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [extraKeysBar.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
        extraKeysBottomConstraint,
        extraKeysHeightConstraint,
    ]];

    // The storyboard pins the text view to the safe-area bottom; re-route it
    // to the pane's top edge so the pane never covers text.
    for (NSLayoutConstraint *constraint in [self.view.constraints copy]) {
        BOOL isTextBottom = (constraint.firstItem == _textInput
                && constraint.firstAttribute == NSLayoutAttributeBottom)
            || (constraint.secondItem == _textInput
                && constraint.secondAttribute == NSLayoutAttributeBottom);
        if (isTextBottom) constraint.active = NO;
    }
    [_textInput.bottomAnchor constraintEqualToAnchor:extraKeysBar.topAnchor].active = YES;
    [self reloadExtraKeysBar];
}

- (void)reloadExtraKeysBar {
    if (!extraKeysBar) return;
    ConfigManager *config = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];
    extraKeysIdentifiers = [ZXEditorAccessoryKeys
        enabledIdentifiersFromStored:[config getValueFromKey:ZX_EDITOR_EXTRA_KEYS_KEY]];
    [extraKeysBar configureWithIdentifiers:extraKeysIdentifiers];
    BOOL empty = (extraKeysIdentifiers.count == 0);
    extraKeysBar.hidden = empty;
    extraKeysHeightConstraint.constant = empty ? 0.0 : ZX_EDITOR_ACCESSORY_BAR_HEIGHT;
    // Toast and completion popup both rest above the pane now.
    toastBottomConstraint.constant = -(12.0 + keyboardBottomInset + [self extraKeysVisibleHeight]);
    [self.view setNeedsLayout];
}

- (CGFloat)extraKeysVisibleHeight {
    if (!extraKeysBar || extraKeysBar.hidden) return 0.0;
    return ZX_EDITOR_ACCESSORY_BAR_HEIGHT;
}

- (void)editorAccessoryView:(UIView *)view
             didActivateKey:(NSString *)identifier
                   repeated:(BOOL)repeated {
    (void)view;
    (void)repeated;
    [self handleExtraKey:identifier repeated:repeated];
}

- (void)handleExtraKey:(NSString *)identifier repeated:(BOOL)repeated {
    (void)repeated;
    // [_textInput insertText:] runs through shouldChangeTextInRange:/didChange,
    // so Tab-to-spaces, auto-indent, highlight and completions all behave
    // exactly as if the text had been typed.
    if ([identifier isEqualToString:ZXEditorKeyEsc]) {
        if (!completionTableView.hidden) [self hideCompletions];
        else [_textInput resignFirstResponder];
    } else if ([identifier isEqualToString:ZXEditorKeyLeft]) {
        [self extraKeysMoveLeft];
    } else if ([identifier isEqualToString:ZXEditorKeyRight]) {
        [self extraKeysMoveRight];
    } else if ([identifier isEqualToString:ZXEditorKeyUp]) {
        [self extraKeysMoveUp];
    } else if ([identifier isEqualToString:ZXEditorKeyDown]) {
        [self extraKeysMoveDown];
    } else if ([identifier isEqualToString:ZXEditorKeyHome]) {
        [self extraKeysMoveHome];
    } else if ([identifier isEqualToString:ZXEditorKeyEnd]) {
        [self extraKeysMoveEnd];
    } else if ([identifier isEqualToString:ZXEditorKeyShiftTab]) {
        [self extraKeysDedentLines];
    } else if ([identifier isEqualToString:ZXEditorKeyComment]) {
        [self extraKeysToggleComment];
    } else if ([identifier isEqualToString:ZXEditorKeyDeleteLine]) {
        [self extraKeysDeleteLine];
    } else if ([identifier isEqualToString:ZXEditorKeyBackspace]) {
        [_textInput deleteBackward];
    } else {
        NSString *text = [ZXEditorAccessoryKeys insertTextForIdentifier:identifier];
        if (text) [_textInput insertText:text];
    }
}

- (void)extraKeysMoveLeft {
    NSRange selected = _textInput.selectedRange;
    NSUInteger position = selected.length > 0 ? selected.location
        : (selected.location > 0 ? selected.location - 1 : 0);
    _textInput.selectedRange = NSMakeRange(position, 0);
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

- (void)extraKeysMoveRight {
    NSRange selected = _textInput.selectedRange;
    NSUInteger end = MIN(NSMaxRange(selected), _textInput.text.length);
    NSUInteger position = selected.length > 0 ? end : MIN(end + 1, _textInput.text.length);
    _textInput.selectedRange = NSMakeRange(position, 0);
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

- (void)extraKeysMoveUp {
    UITextRange *selected = _textInput.selectedTextRange;
    if (!selected) return;
    UITextPosition *position = [_textInput positionFromPosition:selected.start
                                                   inDirection:UITextLayoutDirectionUp
                                                        offset:1];
    if (!position) return;
    _textInput.selectedTextRange = [_textInput textRangeFromPosition:position toPosition:position];
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

- (void)extraKeysMoveDown {
    UITextRange *selected = _textInput.selectedTextRange;
    if (!selected) return;
    UITextPosition *position = [_textInput positionFromPosition:selected.start
                                                   inDirection:UITextLayoutDirectionDown
                                                        offset:1];
    if (!position) return;
    _textInput.selectedTextRange = [_textInput textRangeFromPosition:position toPosition:position];
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

- (void)extraKeysMoveHome {
    NSString *text = _textInput.text ?: @"";
    NSUInteger position = MIN(_textInput.selectedRange.location, text.length);
    while (position > 0 && [text characterAtIndex:position - 1] != '\n') position--;
    _textInput.selectedRange = NSMakeRange(position, 0);
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

- (void)extraKeysMoveEnd {
    NSString *text = _textInput.text ?: @"";
    NSUInteger position = MIN(_textInput.selectedRange.location, text.length);
    while (position < text.length && [text characterAtIndex:position] != '\n') position++;
    _textInput.selectedRange = NSMakeRange(position, 0);
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
    [self updateCompletions];
}

// Block range covering the current selection, expanded to full lines.
- (NSRange)extraKeysSelectedLineBlock:(NSString *)text {
    NSUInteger location = MIN(_textInput.selectedRange.location, text.length);
    NSUInteger end = MIN(NSMaxRange(_textInput.selectedRange), text.length);
    while (location > 0 && [text characterAtIndex:location - 1] != '\n') location--;
    while (end < text.length && [text characterAtIndex:end] != '\n') end++;
    return NSMakeRange(location, end - location);
}

- (void)extraKeysDedentLines {
    NSString *text = _textInput.text ?: @"";
    NSRange block = [self extraKeysSelectedLineBlock:text];
    NSArray<NSString *> *lines = [[text substringWithRange:block] componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *dedented = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSUInteger strip = 0;
        while (strip < ZX_EDITOR_INDENT_WIDTH && strip < line.length
                && [line characterAtIndex:strip] == ' ') strip++;
        if (strip == 0 && line.length > 0 && [line characterAtIndex:0] == '\t') strip = 1;
        [dedented addObject:[line substringFromIndex:strip]];
    }
    isApplyingEdit = YES;
    [_textInput.textStorage replaceCharactersInRange:block
                                          withString:[dedented componentsJoinedByString:@"\n"]];
    _textInput.selectedRange = NSMakeRange(block.location, 0);
    isApplyingEdit = NO;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self updateCompletions];
}

- (void)extraKeysToggleComment {
    NSString *text = _textInput.text ?: @"";
    NSRange block = [self extraKeysSelectedLineBlock:text];
    NSArray<NSString *> *lines = [[text substringWithRange:block] componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *toggled = [NSMutableArray arrayWithCapacity:lines.count];
    for (NSString *line in lines) {
        NSUInteger indent = 0;
        while (indent < line.length && [line characterAtIndex:indent] == ' ') indent++;
        NSString *head = [line substringToIndex:indent];
        NSString *body = [line substringFromIndex:indent];
        if ([body hasPrefix:@"#"]) {
            body = [body substringFromIndex:1];
            if ([body hasPrefix:@" "]) body = [body substringFromIndex:1];
        } else {
            body = [@"# " stringByAppendingString:body];
        }
        [toggled addObject:[head stringByAppendingString:body]];
    }
    isApplyingEdit = YES;
    [_textInput.textStorage replaceCharactersInRange:block
                                          withString:[toggled componentsJoinedByString:@"\n"]];
    _textInput.selectedRange = NSMakeRange(block.location, 0);
    isApplyingEdit = NO;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self updateCompletions];
}

- (void)extraKeysDeleteLine {
    NSString *text = _textInput.text ?: @"";
    if (text.length == 0) return;
    NSRange block = [self extraKeysSelectedLineBlock:text];
    // Swallow one adjacent newline so no blank line is left behind.
    if (NSMaxRange(block) < text.length && [text characterAtIndex:NSMaxRange(block)] == '\n') {
        block = NSMakeRange(block.location, block.length + 1);
    } else if (block.location > 0 && [text characterAtIndex:block.location - 1] == '\n') {
        block = NSMakeRange(block.location - 1, block.length + 1);
    }
    isApplyingEdit = YES;
    [_textInput.textStorage replaceCharactersInRange:block withString:@""];
    _textInput.selectedRange = NSMakeRange(MIN(block.location, _textInput.text.length), 0);
    isApplyingEdit = NO;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self updateCompletions];
}

#pragma mark - Toast

- (void)configureToast {
    toastView = [[UIView alloc] init];
    toastView.translatesAutoresizingMaskIntoConstraints = NO;
    toastView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.85];
    toastView.layer.cornerRadius = 12.0;
    toastView.layer.masksToBounds = YES;
    toastView.alpha = 0.0;
    toastView.hidden = YES;
    [toastView addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleToastTap)]];

    toastLabel = [[UILabel alloc] init];
    toastLabel.translatesAutoresizingMaskIntoConstraints = NO;
    toastLabel.numberOfLines = 0;
    toastLabel.font = [UIFont systemFontOfSize:13.0 weight:UIFontWeightMedium];
    toastLabel.textColor = UIColor.whiteColor;
    toastLabel.textAlignment = NSTextAlignmentCenter;
    [toastView addSubview:toastLabel];

    [self.view addSubview:toastView];
    [NSLayoutConstraint activateConstraints:@[
        [toastLabel.topAnchor constraintEqualToAnchor:toastView.topAnchor constant:10.0],
        [toastLabel.bottomAnchor constraintEqualToAnchor:toastView.bottomAnchor constant:-10.0],
        [toastLabel.leadingAnchor constraintEqualToAnchor:toastView.leadingAnchor constant:16.0],
        [toastLabel.trailingAnchor constraintEqualToAnchor:toastView.trailingAnchor constant:-16.0],
        [toastView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [toastView.leadingAnchor constraintGreaterThanOrEqualToAnchor:self.view.leadingAnchor constant:12.0],
        [toastView.trailingAnchor constraintLessThanOrEqualToAnchor:self.view.trailingAnchor constant:-12.0],
    ]];
    // Sits at the bottom of the editor; the keyboard shifts it up in step.
    toastBottomConstraint = [toastView.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor
                                                                   constant:-12.0];
    toastBottomConstraint.active = YES;
}

- (void)showEditorToast:(NSString *)message isError:(BOOL)isError {
    if (!toastView || message.length == 0) return;
    // Only a changed verdict is worth a new toast: repeating "no errors" after
    // every pause would be noise, while error -> clean still announces itself.
    if (lastToastMessage && [message isEqualToString:lastToastMessage]) return;
    lastToastMessage = [message copy];
    toastHasProblems = isError;
    toastLabel.text = message;
    toastView.backgroundColor = isError
        ? [UIColor.systemRedColor colorWithAlphaComponent:0.92]
        : [[UIColor blackColor] colorWithAlphaComponent:0.85];
    toastView.hidden = NO;
    [self.view bringSubviewToFront:toastView];
    [UIView animateWithDuration:0.2 animations:^{
        self->toastView.alpha = 1.0;
    }];

    [toastTimer invalidate];
    toastTimer = [NSTimer scheduledTimerWithTimeInterval:(isError ? 4.5 : 2.5)
                                                 target:self
                                               selector:@selector(hideEditorToast)
                                               userInfo:nil
                                                repeats:NO];
}

- (void)hideEditorToast {
    [toastTimer invalidate];
    toastTimer = nil;
    if (toastView.hidden) return;
    [UIView animateWithDuration:0.25 animations:^{
        self->toastView.alpha = 0.0;
    } completion:^(BOOL finished) {
        self->toastView.hidden = YES;
    }];
}

- (void)handleToastTap {
    [self hideEditorToast];
    if (toastHasProblems) [self showProblems];
}

#pragma mark - Keyboard

- (void)keyboardWillChangeFrame:(NSNotification *)note {
    CGRect endFrame = [note.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboardInView = [self.view convertRect:endFrame fromView:nil];
    CGFloat overlap = MAX(0.0, CGRectGetHeight(self.view.bounds) - CGRectGetMinY(keyboardInView));
    CGFloat bottomInset = MAX(0.0, overlap - self.view.safeAreaInsets.bottom);
    if (fabs(bottomInset - keyboardBottomInset) < 0.5) return;
    keyboardBottomInset = bottomInset;

    UIEdgeInsets inset = _textInput.contentInset;
    void (^changes)(void) = ^{
        _textInput.contentInset = UIEdgeInsetsMake(inset.top, inset.left, bottomInset, inset.right);
        _textInput.verticalScrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottomInset, 0);
        // The same pane docks at the editor bottom normally and floats above
        // the keyboard here; the toast always rests above the pane.
        self->extraKeysBottomConstraint.constant = -bottomInset;
        self->toastBottomConstraint.constant = -(12.0 + bottomInset + [self extraKeysVisibleHeight]);
        [self.view layoutIfNeeded];
    };

    NSTimeInterval duration = [note.userInfo[UIKeyboardAnimationDurationUserInfoKey] doubleValue];
    UIViewAnimationCurve curve = (UIViewAnimationCurve)[note.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
    if (duration > 0) {
        [UIView animateWithDuration:duration
                              delay:0
                            options:(UIViewAnimationOptions)(curve << 16)
                         animations:changes
                         completion:^(BOOL finished) {
                             // Re-run once the layout settled on the new inset.
                             [self->_textInput scrollRangeToVisible:self->_textInput.selectedRange];
                         }];
    } else {
        changes();
    }
    [self updateLineNumbers];
    // Inset alone only lets the content scroll; pull the caret above the
    // keyboard as well.
    [_textInput scrollRangeToVisible:_textInput.selectedRange];
}

#pragma mark - Line numbers

- (void)applyEditorFontSize {
    _textInput.font = ZXEditorFont();
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self updateLineNumbers];
}

- (void)updateLineNumbers {
    if (!lineNumberView) return;
    [_textInput layoutIfNeeded];
    UIFont *font = _textInput.font ?: [UIFont monospacedSystemFontOfSize:ZX_EDITOR_FONT_SIZE_DEFAULT weight:UIFontWeightRegular];
    NSUInteger lineCount = [ZXPythonEditorSupport lineCountForSource:_textInput.text ?: @""];
    NSUInteger digits = 0;
    for (NSUInteger value = MAX(lineCount, 1); value > 0; value /= 10) digits++;
    CGFloat digitWidth = [@"0" sizeWithAttributes:@{ NSFontAttributeName: font }].width;
    CGFloat gutterWidth = ceil(digitWidth * MAX(digits, 2)) + 2 * ZXLineNumberHorizontalPadding;
    UIEdgeInsets inset = _textInput.textContainerInset;
    CGFloat wantedLeft = gutterWidth + ZXLineNumberTextGap;
    if (fabs(inset.left - wantedLeft) > 0.5) {
        _textInput.textContainerInset = UIEdgeInsetsMake(inset.top, wantedLeft, inset.bottom, inset.right);
        [_textInput layoutIfNeeded];
    }
    lineNumberView.numberFont = font;
    lineNumberView.frame = CGRectMake(0, 0, gutterWidth,
                                      MAX(_textInput.contentSize.height, CGRectGetHeight(_textInput.bounds)));
    // Keep the gutter above the text view's own internal container view.
    [_textInput bringSubviewToFront:lineNumberView];
    // The gutter shares the text view's content coordinates, so the text
    // view's bounds are exactly the band that is on screen.
    [lineNumberView setNeedsDisplayInRect:_textInput.bounds];
}

#pragma mark - Validation

// Checking is manual on purpose: the button is the only thing that starts a
// run, so the editor never pays for a check while the user is still typing.
- (void)checkScript {
    lastToastMessage = nil;
    [self runValidation];
}

- (void)finishPendingSave {
    if (!saveAfterValidation) return;
    saveAfterValidation = NO;
    [self saveFile];
}

- (NSString *)validationFilePath {
    NSString *directory = @"/var/mobile/Library/ZXTouch/tmp";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:@"editor_check.py"];
}

- (void)runValidation {
    if (![self isPythonFile] || isApplyingEdit) {
        [self finishPendingSave];
        return;
    }
    NSString *source = _textInput.text ?: @"";
    validationGeneration += 1;
    NSUInteger generation = validationGeneration;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSArray<NSDictionary *> *results = [strongSelf validateSource:source];
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) main = weakSelf;
            if (!main || generation != main->validationGeneration) return;
            main->diagnostics = results ?: @[];
            main->diagnosticsSource = source;
            [main applySyntaxHighlightingPreservingSelection:YES];
            [main updateValidationStatus];
            [main finishPendingSave];
        });
    });
}

- (NSArray<NSDictionary *> *)validateSource:(NSString *)source {
    NSString *path = [self validationFilePath];
    NSError *error = nil;
    if (![source writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:&error]) return @[];
    NSString *reportPath = [path stringByAppendingString:@".diag.json"];
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];

    // The SpringBoard service runs `python3 -m zxtouch.checker` and writes the
    // report next to the staged file; the reply is only an ack.
    Socket *socket = [[Socket alloc] init];
    if ([socket connect:@"127.0.0.1" byPort:6000] != 0) return @[];
    [socket setReceiveTimeout:30];
    [socket send:[NSString stringWithFormat:@"49%@\r\n", path]];
    [socket recv:256];
    [socket close];

    NSData *data = [NSData dataWithContentsOfFile:reportPath];
    NSArray<NSDictionary *> *results = [ZXPythonEditorSupport diagnosticsFromReportData:data];
    [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:reportPath error:nil];
    return results;
}

- (void)applyDiagnosticsToAttributedString:(NSMutableAttributedString *)attributed source:(NSString *)source {
    if (diagnostics.count == 0) return;
    // Ranges were computed for a specific revision; skip until the fresh
    // result arrives instead of painting stale positions.
    if (diagnosticsSource && ![diagnosticsSource isEqualToString:source]) return;
    NSArray<NSDictionary *> *annotations = [ZXPythonEditorSupport rangesForDiagnostics:diagnostics inSource:source];
    for (NSDictionary *annotation in annotations) {
        NSRange range = [annotation[@"range"] rangeValue];
        if (range.length == 0 || NSMaxRange(range) > attributed.length) continue;
        BOOL isError = ![annotation[@"severity"] isEqualToString:@"warning"];
        UIColor *color = isError ? UIColor.systemRedColor : UIColor.systemOrangeColor;
        [attributed addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:range];
        [attributed addAttribute:NSUnderlineColorAttributeName value:color range:range];
        [attributed addAttribute:NSBackgroundColorAttributeName value:[color colorWithAlphaComponent:0.12] range:range];
    }
}

- (NSInteger)errorCount {
    NSInteger count = 0;
    for (NSDictionary *item in diagnostics) {
        if ([item[@"severity"] isEqualToString:@"error"]) count += 1;
    }
    return count;
}

- (void)updateValidationStatus {
    if (![self isPythonFile]) {
        [self refreshBarButtons];
        return;
    }
    if (diagnostics.count == 0) {
        [self showEditorToast:@"✓ Không phát hiện lỗi" isError:NO];
        [self refreshBarButtons];
        return;
    }
    NSInteger errors = 0, warnings = 0;
    NSDictionary *first = diagnostics.firstObject;
    BOOL foundError = NO;
    for (NSDictionary *item in diagnostics) {
        if ([item[@"severity"] isEqualToString:@"warning"]) { warnings += 1; continue; }
        if ([item[@"severity"] isEqualToString:@"error"]) { errors += 1; }
        if (!foundError) { first = item; foundError = YES; }
    }
    NSString *message = errors > 0
        ? [NSString stringWithFormat:@"%ld lỗi, %ld cảnh báo — dòng %@", (long)errors, (long)warnings, first[@"line"] ?: @0]
        : [NSString stringWithFormat:@"%ld cảnh báo — dòng %@", (long)warnings, first[@"line"] ?: @0];
    [self showEditorToast:message isError:errors > 0];
    [self refreshBarButtons];
}

- (void)showProblems {
    if (diagnostics.count == 0) return;
    NSMutableString *message = [NSMutableString string];
    for (NSDictionary *item in diagnostics) {
        [message appendFormat:@"Dòng %@ — %@\n", item[@"line"] ?: @0, item[@"message"] ?: @""];
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Problems"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)saveFile {
    // The verdict has to match the text being saved: a stale result would warn
    // about errors the user already fixed, or miss the ones just typed.
    NSString *source = _textInput.text ?: @"";
    if ([self isPythonFile] && ![source isEqualToString:diagnosticsSource ?: @""]) {
        saveAfterValidation = YES;
        [self runValidation];
        return;
    }
    NSInteger errors = [self errorCount];
    if (errors > 0) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Code còn lỗi"
                                                                       message:[NSString stringWithFormat:@"Script còn %ld lỗi theo kiểm tra. Vẫn lưu?", (long)errors]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"Huỷ" style:UIAlertActionStyleCancel handler:nil]];
        __weak typeof(self) weakSelf = self;
        [alert addAction:[UIAlertAction actionWithTitle:@"Vẫn lưu" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            [weakSelf writeFile];
        }]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self writeFile];
}

- (void)writeFile {
    NSError *err = nil;
    [[_textInput text] writeToFile:currentFilePath atomically:YES encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        NSLog(@"Error while saving file. Error: %@", err);
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error"
                                                                         message:[NSString stringWithFormat:@"Error saving file. Error message: %@", err]
                                                                  preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    [self hideSaveButton];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end
