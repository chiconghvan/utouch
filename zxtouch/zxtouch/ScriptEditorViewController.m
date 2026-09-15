#import "ScriptEditorViewController.h"
#import "ZXPythonEditorSupport.h"
#import "Socket.h"

@interface ScriptEditorViewController () <UITableViewDataSource, UITableViewDelegate>
- (void)refreshBarButtons;
- (void)scheduleValidation;
- (void)runValidation;
- (NSString *)validationFilePath;
- (NSArray<NSDictionary *> *)validateSource:(NSString *)source;
- (void)applyDiagnosticsToAttributedString:(NSMutableAttributedString *)attributed source:(NSString *)source;
- (NSInteger)errorCount;
- (void)updateValidationStatus;
- (void)showProblems;
- (void)writeFile;
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
    UIBarButtonItem *formatButton;
    UIBarButtonItem *saveButton;
    UIBarButtonItem *problemsButton;
    NSTimer *validationTimer;
    NSArray<NSDictionary *> *diagnostics;
    NSString *diagnosticsSource;
    NSUInteger validationGeneration;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    NSString *content = [NSString stringWithContentsOfFile:currentFilePath
                                                   encoding:NSUTF8StringEncoding
                                                      error:NULL] ?: @"";
    _textInput.text = content;
    _textInput.font = [UIFont monospacedSystemFontOfSize:14 weight:UIFontWeightRegular];
    _textInput.autocorrectionType = UITextAutocorrectionTypeNo;
    _textInput.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _textInput.smartDashesType = UITextSmartDashesTypeNo;
    _textInput.smartQuotesType = UITextSmartQuotesTypeNo;
    _textInput.delegate = self;
    _textInput.textContainerInset = UIEdgeInsetsMake(10, 8, 10, 8);
    [self configureCompletionTable];
    if ([self isPythonFile]) {
        formatButton = [[UIBarButtonItem alloc] initWithTitle:@"Format"
                                                        style:UIBarButtonItemStylePlain
                                                       target:self
                                                       action:@selector(formatFile)];
        [self refreshBarButtons];
    }
    [self applySyntaxHighlightingPreservingSelection:NO];
    isSaveButtonShown = NO;
    [self scheduleValidation];
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
}

- (void)refreshBarButtons {
    NSMutableArray<UIBarButtonItem *> *items = [NSMutableArray array];
    if (formatButton) [items addObject:formatButton];
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
    if (!completionTableView.hidden) [self positionCompletionTable];
}

- (void)textViewDidChange:(UITextView *)textView {
    if (isApplyingHighlight || isApplyingEdit) return;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self updateCompletions];
    [self scheduleValidation];
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
        [self scheduleValidation];
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
    if (y + height > CGRectGetHeight(self.view.bounds) - 12.0) y = MAX(12.0, CGRectGetMinY(caretInView) - height - 4.0);
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
    [self scheduleValidation];
}

#pragma mark - Validation

- (void)scheduleValidation {
    [validationTimer invalidate];
    if (![self isPythonFile]) return;
    validationTimer = [NSTimer scheduledTimerWithTimeInterval:0.6
                                                       target:self
                                                     selector:@selector(runValidation)
                                                     userInfo:nil
                                                      repeats:NO];
}

- (NSString *)validationFilePath {
    NSString *directory = @"/var/mobile/Library/ZXTouch/tmp";
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    return [directory stringByAppendingPathComponent:@"editor_check.py"];
}

- (void)runValidation {
    if (![self isPythonFile] || isApplyingEdit) return;
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
        self.navigationItem.prompt = nil;
        [self refreshBarButtons];
        return;
    }
    if (diagnostics.count == 0) {
        self.navigationItem.prompt = @"✓ Không phát hiện lỗi";
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
    self.navigationItem.prompt = [NSString stringWithFormat:@"%ld lỗi, %ld cảnh báo — dòng %@",
                                  (long)errors, (long)warnings, first[@"line"] ?: @0];
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

- (void)formatFile {
    if (![self isPythonFile]) return;
    NSString *formatted = [ZXPythonEditorSupport formatSource:_textInput.text ?: @""];
    if ([formatted isEqualToString:_textInput.text ?: @""]) return;
    NSUInteger oldCursor = _textInput.selectedRange.location;
    NSUInteger newCursor = MIN(oldCursor, formatted.length);
    if (oldCursor <= _textInput.text.length) {
        NSString *prefix = [_textInput.text substringToIndex:oldCursor];
        newCursor = MIN([ZXPythonEditorSupport formatSource:prefix].length, formatted.length);
    }
    isApplyingEdit = YES;
    _textInput.text = formatted;
    _textInput.selectedRange = NSMakeRange(newCursor, 0);
    isApplyingEdit = NO;
    [self applySyntaxHighlightingPreservingSelection:YES];
    [self showSaveButton];
    [self hideCompletions];
    [self scheduleValidation];
}

- (void)saveFile {
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
    [validationTimer invalidate];
    validationTimer = nil;
}

@end
