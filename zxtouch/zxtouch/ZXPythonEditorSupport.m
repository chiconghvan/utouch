#import "ZXPythonEditorSupport.h"
#import "Config.h"

static NSCharacterSet *ZXIdentifierStartSet(void)
{
    static NSCharacterSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"];
    });
    return set;
}

static NSCharacterSet *ZXIdentifierSet(void)
{
    static NSCharacterSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_0123456789"];
    });
    return set;
}

static NSSet *ZXPythonKeywords(void)
{
    static NSSet *set;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        set = [NSSet setWithObjects:@"False", @"None", @"True", @"and", @"as", @"assert", @"async", @"await", @"break", @"class", @"continue", @"def", @"del", @"elif", @"else", @"except", @"finally", @"for", @"from", @"global", @"if", @"import", @"in", @"is", @"lambda", @"nonlocal", @"not", @"or", @"pass", @"raise", @"return", @"try", @"while", @"with", @"yield", nil];
    });
    return set;
}

static NSDictionary *ZXCompletion(NSString *name, NSString *signature, NSString *outputType, NSString *kind)
{
    return @{ @"name": name,
              @"signature": signature.length ? signature : [NSString stringWithFormat:@"%@()", name],
              @"documentation": signature.length ? signature : name,
              @"outputType": outputType.length ? outputType : @"unknown",
              @"kind": kind.length ? kind : @"function",
              @"insertText": [kind isEqualToString:@"function"] ? [NSString stringWithFormat:@"%@()", name] : name };
}

static NSArray<NSDictionary *> *ZXKeywordCompletions(void)
{
    static NSArray *items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray *keywords = [NSMutableArray array];
        for (NSString *keyword in [ZXPythonKeywords() allObjects]) {
            [keywords addObject:ZXCompletion(keyword, keyword, @"syntax construct", @"keyword")];
        }
        items = [keywords copy];
    });
    return items;
}

static NSArray<NSDictionary *> *ZXFallbackCompletions(void)
{
    static NSArray *items;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        items = @[
            ZXCompletion(@"tap", @"tap(x: number, y: number)", @"void", @"function"),
            ZXCompletion(@"touchDown", @"touchDown(finger: number, x: number, y: number)", @"void", @"function"),
            ZXCompletion(@"touchMove", @"touchMove(finger: number, x: number, y: number)", @"void", @"function"),
            ZXCompletion(@"touchUp", @"touchUp(finger: number)", @"void", @"function"),
            ZXCompletion(@"swipe", @"swipe(x1: number, y1: number, x2: number, y2: number, duration: number)", @"void", @"function"),
            ZXCompletion(@"longPress", @"longPress(x: number, y: number, duration: number)", @"void", @"function"),
            ZXCompletion(@"getColor", @"getColor(x: number, y: number)", @"number", @"function"),
            ZXCompletion(@"findColor", @"findColor(color: number, region: table)", @"[number, number][]", @"function"),
            ZXCompletion(@"findImage", @"findImage(path: text, count: number = None, threshold: number = 0.8, region: table = None)", @"object[]", @"function"),
            ZXCompletion(@"ocrText", @"ocrText(region: table = None)", @"string", @"function"),
            ZXCompletion(@"findText", @"findText(text: string, region: table = None)", @"object[]", @"function"),
            ZXCompletion(@"tapImage", @"tapImage(path: text, region: table = None)", @"object | null", @"function"),
            ZXCompletion(@"dialogInput", @"dialogInput(title: text, message: text)", @"string", @"function"),
            ZXCompletion(@"dialogChoice", @"dialogChoice(title: text, options: table)", @"number", @"function"),
            ZXCompletion(@"toast", @"toast(message: text)", @"boolean", @"function"),
            ZXCompletion(@"alert", @"alert(message: text)", @"boolean", @"function"),
            ZXCompletion(@"log", @"log(message: text)", @"boolean", @"function"),
            ZXCompletion(@"sleep", @"sleep(seconds: number)", @"void", @"function"),
            ZXCompletion(@"usleep", @"usleep(microseconds: number)", @"void", @"function"),
            ZXCompletion(@"randomSleep", @"randomSleep(minimum: number, maximum: number)", @"void", @"function"),
            ZXCompletion(@"screenSize", @"screenSize()", @"object", @"function"),
            ZXCompletion(@"deviceInfo", @"deviceInfo()", @"object", @"function"),
            ZXCompletion(@"appRun", @"appRun(bundleid: text)", @"boolean", @"function"),
            ZXCompletion(@"appKill", @"appKill(bundleid: text)", @"boolean", @"function"),
            ZXCompletion(@"appState", @"appState(bundleid: text)", @"number", @"function"),
            ZXCompletion(@"inputText", @"inputText(text: text)", @"boolean", @"function"),
            ZXCompletion(@"getClipboard", @"getClipboard()", @"string", @"function"),
            ZXCompletion(@"setClipboard", @"setClipboard(text: text)", @"boolean", @"function"),
            ZXCompletion(@"httpGet", @"httpGet(url: text, headers: table = None)", @"HttpResponse", @"function"),
            ZXCompletion(@"httpPost", @"httpPost(url: text, body: any = None, headers: table = None)", @"HttpResponse", @"function"),
            ZXCompletion(@"readFile", @"readFile(path: text)", @"string", @"function"),
            ZXCompletion(@"writeFile", @"writeFile(path: text, content: text)", @"boolean", @"function"),
            ZXCompletion(@"jsonEncode", @"jsonEncode(value: any)", @"string", @"function"),
            ZXCompletion(@"jsonDecode", @"jsonDecode(value: string)", @"object", @"function"),
            ZXCompletion(@"crane.list", @"crane.list(bundleid: text)", @"object[]", @"function"),
            ZXCompletion(@"crane.switch", @"crane.switch(bundleid: text, account: text)", @"object", @"function"),
            ZXCompletion(@"crane.create", @"crane.create(bundleid: text, account: text)", @"object", @"function"),
            ZXCompletion(@"crane.delete", @"crane.delete(bundleid: text, account: text)", @"object", @"function"),
        ];
    });
    return items;
}

static BOOL ZXIsIdentifierStart(unichar character)
{
    return [ZXIdentifierStartSet() characterIsMember:character];
}

static BOOL ZXIsIdentifierCharacter(unichar character)
{
    return [ZXIdentifierSet() characterIsMember:character] || (character >= '0' && character <= '9');
}

static BOOL ZXIsTripleQuoteAt(NSString *source, NSUInteger location, NSString **quote)
{
    if (location + 3 > source.length) return NO;
    NSString *part = [source substringWithRange:NSMakeRange(location, 3)];
    if ([part isEqualToString:@"\"\"\""] || [part isEqualToString:@"'''"]) {
        if (quote) *quote = part;
        return YES;
    }
    return NO;
}

static BOOL ZXLineHasCodeColon(NSString *line)
{
    BOOL single = NO;
    BOOL doubleQuote = NO;
    BOOL escaped = NO;
    for (NSUInteger index = 0; index < line.length; index++) {
        unichar character = [line characterAtIndex:index];
        if (escaped) { escaped = NO; continue; }
        if ((single || doubleQuote) && character == '\\') { escaped = YES; continue; }
        if (!doubleQuote && character == '\'') { single = !single; continue; }
        if (!single && character == '"') { doubleQuote = !doubleQuote; continue; }
        if (!single && !doubleQuote && character == '#') break;
        if (!single && !doubleQuote && character == ':') {
            NSString *tail = [line substringFromIndex:index + 1];
            if ([[tail stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) return YES;
        }
    }
    return NO;
}

static NSUInteger ZXLeadingSpaces(NSString *line)
{
    NSUInteger spaces = 0;
    for (NSUInteger index = 0; index < line.length; index++) {
        unichar character = [line characterAtIndex:index];
        if (character == ' ') spaces++;
        else if (character == '\t') spaces += 4;
        else break;
    }
    return spaces;
}

static NSString *ZXLeadingWhitespace(NSString *line)
{
    NSUInteger index = 0;
    while (index < line.length) {
        unichar character = [line characterAtIndex:index];
        if (character != ' ' && character != '\t') break;
        index++;
    }
    return [line substringToIndex:index];
}

static NSString *ZXTrimTrailingWhitespace(NSString *line)
{
    return [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
}

@implementation ZXPythonEditorSupport

+ (NSString *)formatSource:(NSString *)source
{
    if (source.length == 0) return @"";
    NSArray *lines = [source componentsSeparatedByString:@"\n"];
    NSMutableArray *formatted = [NSMutableArray arrayWithCapacity:lines.count];
    NSUInteger continuationDepth = 0;
    BOOL inTripleString = NO;
    NSString *tripleQuote = nil;
    for (NSString *originalLine in lines) {
        NSString *line = originalLine;
        NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (inTripleString) {
            [formatted addObject:line];
            if ([line rangeOfString:tripleQuote].location != NSNotFound) {
                inTripleString = NO;
                tripleQuote = nil;
            }
            continue;
        }
        NSUInteger leading = ZXLeadingSpaces(line);
        NSString *body = [line substringFromIndex:MIN(line.length, [ZXLeadingWhitespace(line) length])];
        body = ZXTrimTrailingWhitespace(body);
        if (trimmed.length == 0) {
            [formatted addObject:@""];
            continue;
        }
        NSUInteger tripleCount = 0;
        NSString *detectedTripleQuote = nil;
        for (NSString *candidate in @[@"\"\"\"", @"'''"]) {
            NSUInteger searchLocation = 0;
            NSUInteger count = 0;
            while (searchLocation + candidate.length <= body.length) {
                NSRange found = [body rangeOfString:candidate options:0 range:NSMakeRange(searchLocation, body.length - searchLocation)];
                if (found.location == NSNotFound) break;
                count++;
                searchLocation = NSMaxRange(found);
            }
            if (count % 2 == 1) {
                detectedTripleQuote = candidate;
                tripleCount = count;
                break;
            }
        }
        if (tripleCount % 2 == 1) {
            tripleQuote = detectedTripleQuote;
            inTripleString = YES;
        }
        BOOL dedent = [trimmed hasPrefix:@"else:"] || [trimmed hasPrefix:@"elif "] || [trimmed hasPrefix:@"except"] || [trimmed hasPrefix:@"finally:"];
        NSUInteger outputIndent = leading;
        if (dedent && outputIndent >= ZX_EDITOR_INDENT_WIDTH) outputIndent -= ZX_EDITOR_INDENT_WIDTH;
        if (continuationDepth > 0 && !dedent && outputIndent < continuationDepth * ZX_EDITOR_INDENT_WIDTH) outputIndent = continuationDepth * ZX_EDITOR_INDENT_WIDTH;
        NSMutableString *prefix = [NSMutableString string];
        for (NSUInteger index = 0; index < outputIndent; index++) [prefix appendString:@" "];
        [formatted addObject:[prefix stringByAppendingString:body]];
        NSString *code = body;
        BOOL commentOnly = [code hasPrefix:@"#"];
        if (!commentOnly) {
            NSUInteger open = 0;
            NSUInteger close = 0;
            BOOL single = NO;
            BOOL doubleQuote = NO;
            BOOL escaped = NO;
            for (NSUInteger index = 0; index < code.length; index++) {
                unichar character = [code characterAtIndex:index];
                if (escaped) { escaped = NO; continue; }
                if ((single || doubleQuote) && character == '\\') { escaped = YES; continue; }
                if (!doubleQuote && character == '\'') { single = !single; continue; }
                if (!single && character == '"') { doubleQuote = !doubleQuote; continue; }
                if (single || doubleQuote) continue;
                if (character == '(' || character == '[' || character == '{') open++;
                else if (character == ')' || character == ']' || character == '}') close++;
            }
            continuationDepth = open > close ? open - close : 0;
        }
    }
    return [formatted componentsJoinedByString:@"\n"];
}

+ (NSString *)indentationForNewLineAfterText:(NSString *)text cursorLocation:(NSUInteger)cursorLocation
{
    NSUInteger cursor = MIN(cursorLocation, text.length);
    NSRange lineRange = [text lineRangeForRange:NSMakeRange(cursor > 0 ? cursor - 1 : 0, 0)];
    NSString *line = [text substringWithRange:lineRange];
    NSString *lineWithoutNewline = [line stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
    NSUInteger spaces = ZXLeadingSpaces(lineWithoutNewline);
    NSString *body = [lineWithoutNewline substringFromIndex:MIN(lineWithoutNewline.length, [ZXLeadingWhitespace(lineWithoutNewline) length])];
    if (ZXLineHasCodeColon(body)) spaces += ZX_EDITOR_INDENT_WIDTH;
    NSUInteger continuation = 0;
    BOOL single = NO;
    BOOL doubleQuote = NO;
    BOOL escaped = NO;
    for (NSUInteger index = 0; index < body.length; index++) {
        unichar character = [body characterAtIndex:index];
        if (escaped) { escaped = NO; continue; }
        if ((single || doubleQuote) && character == '\\') { escaped = YES; continue; }
        if (!doubleQuote && character == '\'') { single = !single; continue; }
        if (!single && character == '"') { doubleQuote = !doubleQuote; continue; }
        if (single || doubleQuote) continue;
        if (character == '(' || character == '[' || character == '{') continuation++;
        else if (character == ')' || character == ']' || character == '}') {
            if (continuation > 0) continuation--;
        }
    }
    if (continuation > 0) spaces = MAX(spaces, ZXLeadingSpaces(lineWithoutNewline) + ZX_EDITOR_INDENT_WIDTH);
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger index = 0; index < spaces; index++) [result appendString:@" "];
    return result;
}

+ (NSArray<NSDictionary *> *)tokensForSource:(NSString *)source
{
    NSMutableArray *tokens = [NSMutableArray array];
    NSUInteger index = 0;
    BOOL inString = NO;
    BOOL triple = NO;
    NSString *quote = nil;
    while (index < source.length) {
        unichar character = [source characterAtIndex:index];
        if (inString) {
            NSUInteger start = index;
            BOOL escaped = NO;
            while (index < source.length) {
                if (!triple && !escaped && [source characterAtIndex:index] == [quote characterAtIndex:0]) {
                    index++;
                    inString = NO;
                    break;
                }
                if (triple && !escaped && index + 3 <= source.length && [[source substringWithRange:NSMakeRange(index, 3)] isEqualToString:quote]) {
                    index += 3;
                    inString = NO;
                    break;
                }
                unichar current = [source characterAtIndex:index];
                escaped = current == '\\' && !escaped;
                if (current != '\\') escaped = NO;
                index++;
            }
            [tokens addObject:@{ @"type": @"string", @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            triple = NO;
            quote = nil;
            continue;
        }
        if (character == '#') {
            NSUInteger start = index;
            while (index < source.length && [source characterAtIndex:index] != '\n') index++;
            [tokens addObject:@{ @"type": @"comment", @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            continue;
        }
        NSString *tripleQuote = nil;
        if (ZXIsTripleQuoteAt(source, index, &tripleQuote)) {
            NSUInteger start = index;
            index += 3;
            inString = YES;
            triple = YES;
            quote = tripleQuote;
            while (index + 3 <= source.length && ![[source substringWithRange:NSMakeRange(index, 3)] isEqualToString:quote]) index++;
            if (index + 3 <= source.length) index += 3;
            inString = NO;
            triple = NO;
            quote = nil;
            [tokens addObject:@{ @"type": @"string", @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            continue;
        }
        if (character == '\'' || character == '"') {
            NSUInteger start = index;
            unichar delimiter = character;
            index++;
            BOOL escaped = NO;
            while (index < source.length) {
                unichar current = [source characterAtIndex:index++];
                if (escaped) { escaped = NO; continue; }
                if (current == '\\') { escaped = YES; continue; }
                if (current == delimiter) break;
            }
            [tokens addObject:@{ @"type": @"string", @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            continue;
        }
        if (ZXIsIdentifierStart(character)) {
            NSUInteger start = index++;
            while (index < source.length && ZXIsIdentifierCharacter([source characterAtIndex:index])) index++;
            NSString *word = [source substringWithRange:NSMakeRange(start, index - start)];
            NSString *type = [ZXPythonKeywords() containsObject:word] ? @"keyword" : @"identifier";
            NSUInteger next = index;
            while (next < source.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[source characterAtIndex:next]]) next++;
            if (![type isEqualToString:@"keyword"] && next < source.length && [source characterAtIndex:next] == '(') type = @"call";
            [tokens addObject:@{ @"type": type, @"text": word, @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            continue;
        }
        if (character >= '0' && character <= '9') {
            NSUInteger start = index++;
            while (index < source.length) {
                unichar number = [source characterAtIndex:index];
                if (!((number >= '0' && number <= '9') || number == '.' || number == '_')) break;
                index++;
            }
            [tokens addObject:@{ @"type": @"number", @"range": [NSValue valueWithRange:NSMakeRange(start, index - start)] }];
            continue;
        }
        index++;
    }
    return tokens;
}

+ (NSArray<NSDictionary *> *)completionsForSource:(NSString *)source cursorLocation:(NSUInteger)cursorLocation
{
    NSUInteger cursor = MIN(cursorLocation, source.length);
    NSString *before = [source substringToIndex:cursor];
    NSArray *tokens = [self tokensForSource:before];
    for (NSDictionary *token in tokens) {
        NSRange range = [token[@"range"] rangeValue];
        if (cursor > range.location && cursor <= NSMaxRange(range) && ([token[@"type"] isEqualToString:@"comment"] || [token[@"type"] isEqualToString:@"string"])) return @[];
    }
    NSRegularExpression *prefixRegex = [NSRegularExpression regularExpressionWithPattern:@"([A-Za-z_][A-Za-z0-9_]*(?:\\.[A-Za-z_][A-Za-z0-9_]*)?)$" options:0 error:nil];
    NSTextCheckingResult *match = [prefixRegex firstMatchInString:before options:0 range:NSMakeRange(0, before.length)];
    NSString *prefix = match ? [before substringWithRange:[match rangeAtIndex:1]] : @"";
    NSMutableArray *items = [NSMutableArray arrayWithArray:ZXFallbackCompletions()];
    [items addObjectsFromArray:ZXKeywordCompletions()];
    // Resolve the jbroot prefix from our own bundle path so this also works
    // under roothide's randomized prefix (no libroothide in the Xcode app
    // target): $JBROOT/Applications/zxtouch.app -> $JBROOT. Rootless keeps
    // working via the /var/jb fallback below.
    NSMutableArray *paths = [NSMutableArray array];
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSString *suffix = @"/Applications/zxtouch.app";
    if ([bundlePath hasSuffix:suffix]) {
        NSString *prefix = [bundlePath substringToIndex:bundlePath.length - suffix.length];
        if (prefix.length == 0) prefix = @"/";
        [paths addObject:[prefix stringByAppendingPathComponent:@"usr/share/zxtouch/python/zxtouch/prelude.py"]];
    }
    [paths addObjectsFromArray:@[@"/var/jb/usr/share/zxtouch/python/zxtouch/prelude.py", @"/usr/share/zxtouch/python/zxtouch/prelude.py"]];
    NSString *prelude = nil;
    for (NSString *path in paths) {
        prelude = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
        if (prelude.length) break;
    }
    if (prelude.length) {
        NSRange allStart = [prelude rangeOfString:@"__all__ = ["];
        NSRange allEnd = allStart.location == NSNotFound ? NSMakeRange(NSNotFound, 0) : [prelude rangeOfString:@"\n]" options:0 range:NSMakeRange(NSMaxRange(allStart), prelude.length - NSMaxRange(allStart))];
        NSString *all = allEnd.location == NSNotFound ? @"" : [prelude substringWithRange:NSMakeRange(NSMaxRange(allStart), allEnd.location - NSMaxRange(allStart))];
        NSRegularExpression *quoted = [NSRegularExpression regularExpressionWithPattern:@"\\\"([A-Za-z_]\\w*)\\\"" options:0 error:nil];
        NSRegularExpression *definitions = [NSRegularExpression regularExpressionWithPattern:@"^def\\s+([A-Za-z_]\\w*)\\s*\\((.*?)\\)\\s*:" options:NSRegularExpressionDotMatchesLineSeparators | NSRegularExpressionAnchorsMatchLines error:nil];
        NSMutableSet *exported = [NSMutableSet set];
        for (NSTextCheckingResult *result in [quoted matchesInString:all options:0 range:NSMakeRange(0, all.length)]) [exported addObject:[all substringWithRange:[result rangeAtIndex:1]]];
        NSMutableDictionary *signatures = [NSMutableDictionary dictionary];
        for (NSTextCheckingResult *result in [definitions matchesInString:prelude options:0 range:NSMakeRange(0, prelude.length)]) {
            NSString *name = [prelude substringWithRange:[result rangeAtIndex:1]];
            if ([exported containsObject:name]) {
                NSString *args = [prelude substringWithRange:[result rangeAtIndex:2]];
                args = [args stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
                signatures[name] = [NSString stringWithFormat:@"%@(%@)", name, args];
            }
        }
        for (NSDictionary *item in [items copy]) {
            NSString *name = item[@"name"];
            NSString *signature = signatures[name];
            if (signature.length) {
                NSUInteger itemIndex = [items indexOfObject:item];
                NSMutableDictionary *updated = [item mutableCopy];
                updated[@"signature"] = signature;
                updated[@"documentation"] = signature;
                updated[@"insertText"] = [NSString stringWithFormat:@"%@()", name];
                items[itemIndex] = updated;
            }
        }
        for (NSString *name in exported) {
            if ([signatures[name] length] == 0 || [items filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"name == %@", name]].count) continue;
            [items addObject:ZXCompletion(name, signatures[name], @"unknown", @"function")];
        }
    }
    NSMutableSet *existing = [NSMutableSet set];
    for (NSDictionary *item in items) [existing addObject:item[@"name"]];
    void (^addSymbol)(NSString *) = ^(NSString *name) {
        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (name.length == 0 || [existing containsObject:name] || [ZXPythonKeywords() containsObject:name]) return;
        if (![name rangeOfString:@"^[A-Za-z_]\\w*$" options:NSRegularExpressionSearch].length) return;
        [items addObject:ZXCompletion(name, name, @"variable", @"variable")];
        [existing addObject:name];
    };
    NSRegularExpression *definitionRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bdef\\s+([A-Za-z_]\\w*)\\s*\\(([^)]*)\\)" options:0 error:nil];
    for (NSTextCheckingResult *result in [definitionRegex matchesInString:source options:0 range:NSMakeRange(0, source.length)]) {
        addSymbol([source substringWithRange:[result rangeAtIndex:1]]);
        NSString *parameters = [source substringWithRange:[result rangeAtIndex:2]];
        for (NSString *parameter in [parameters componentsSeparatedByString:@","]) {
            NSString *name = [[[parameter componentsSeparatedByString:@"="] firstObject] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            name = [name stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"* "]];
            addSymbol(name);
        }
    }
    NSRegularExpression *loopRegex = [NSRegularExpression regularExpressionWithPattern:@"\\bfor\\s+([A-Za-z_]\\w*)\\s+in\\b" options:0 error:nil];
    for (NSTextCheckingResult *result in [loopRegex matchesInString:source options:0 range:NSMakeRange(0, source.length)]) addSymbol([source substringWithRange:[result rangeAtIndex:1]]);
    NSRegularExpression *importRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*import\\s+([A-Za-z_]\\w*)" options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSTextCheckingResult *result in [importRegex matchesInString:source options:0 range:NSMakeRange(0, source.length)]) addSymbol([source substringWithRange:[result rangeAtIndex:1]]);
    NSRegularExpression *fromImportRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*from\\s+\\S+\\s+import\\s+([A-Za-z_]\\w*)" options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSTextCheckingResult *result in [fromImportRegex matchesInString:source options:0 range:NSMakeRange(0, source.length)]) addSymbol([source substringWithRange:[result rangeAtIndex:1]]);
    NSRegularExpression *assignmentRegex = [NSRegularExpression regularExpressionWithPattern:@"^\\s*([A-Za-z_]\\w*)\\s*=" options:NSRegularExpressionAnchorsMatchLines error:nil];
    for (NSTextCheckingResult *result in [assignmentRegex matchesInString:source options:0 range:NSMakeRange(0, source.length)]) addSymbol([source substringWithRange:[result rangeAtIndex:1]]);
    NSPredicate *filter = [NSPredicate predicateWithBlock:^BOOL(NSDictionary *item, NSDictionary *bindings) {
        NSString *name = item[@"name"];
        return prefix.length == 0 || [name hasPrefix:prefix];
    }];
    NSArray *filtered = [items filteredArrayUsingPredicate:filter];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
        BOOL leftVariable = [left[@"kind"] isEqualToString:@"variable"];
        BOOL rightVariable = [right[@"kind"] isEqualToString:@"variable"];
        if (leftVariable != rightVariable) return leftVariable ? NSOrderedAscending : NSOrderedDescending;
        return [left[@"name"] compare:right[@"name"]];
    }];
}

+ (NSUInteger)lineCountForSource:(NSString *)source
{
    NSString *text = source ?: @"";
    NSUInteger lines = 1;
    for (NSUInteger index = 0; index < text.length; index++) {
        if ([text characterAtIndex:index] == '\n') lines++;
    }
    return lines;
}

+ (NSArray<NSDictionary *> *)diagnosticsFromReportData:(NSData *)data
{
    if (data.length == 0) return @[];
    id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return @[];
    id list = ((NSDictionary *)json)[@"diagnostics"];
    if (![list isKindOfClass:[NSArray class]]) return @[];
    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (id raw in (NSArray *)list) {
        if (![raw isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *entry = raw;
        id line = [entry[@"line"] isKindOfClass:[NSNumber class]] ? entry[@"line"] : @1;
        id endLine = [entry[@"endLine"] isKindOfClass:[NSNumber class]] ? entry[@"endLine"] : line;
        id column = [entry[@"column"] isKindOfClass:[NSNumber class]] ? entry[@"column"] : @1;
        id endColumn = [entry[@"endColumn"] isKindOfClass:[NSNumber class]] ? entry[@"endColumn"] : column;
        [out addObject:@{
            @"code": [entry[@"code"] isKindOfClass:[NSString class]] ? entry[@"code"] : @"",
            @"severity": [entry[@"severity"] isKindOfClass:[NSString class]] ? entry[@"severity"] : @"error",
            @"line": line,
            @"column": column,
            @"endLine": endLine,
            @"endColumn": endColumn,
            @"message": [entry[@"message"] isKindOfClass:[NSString class]] ? entry[@"message"] : @"",
        }];
    }
    return out;
}

+ (NSUInteger)offsetForLine:(NSInteger)line column:(id)rawColumn lineStarts:(NSArray<NSNumber *> *)lineStarts textLength:(NSUInteger)length
{
    if (line < 1 || (NSUInteger)line > lineStarts.count) return length;
    NSUInteger lineStart = [lineStarts[(NSUInteger)line - 1] unsignedIntegerValue];
    BOOL lastLine = (NSUInteger)line == lineStarts.count;
    // lineStarts[line] is the offset just past the "\n", so a non-final line's
    // content ends one unit earlier.
    NSUInteger lineEnd = lastLine ? length : MAX(lineStart, [lineStarts[(NSUInteger)line] unsignedIntegerValue] - 1);
    NSInteger column = [rawColumn respondsToSelector:@selector(integerValue)] ? [rawColumn integerValue] : 1;
    if (column < 1) column = 1;
    return lineStart + MIN((NSUInteger)(column - 1), lineEnd - lineStart);
}

+ (NSArray<NSDictionary *> *)rangesForDiagnostics:(NSArray<NSDictionary *> *)diagnostics inSource:(NSString *)source
{
    NSString *text = source ?: @"";
    NSUInteger length = text.length;

    // Start offset of every line, in UTF-16 units (matches NSRange).
    NSMutableArray<NSNumber *> *lineStarts = [NSMutableArray arrayWithObject:@(0)];
    NSUInteger cursor = 0;
    while (cursor < length) {
        NSRange newline = [text rangeOfString:@"\n" options:0 range:NSMakeRange(cursor, length - cursor)];
        if (newline.location == NSNotFound) break;
        cursor = NSMaxRange(newline);
        [lineStarts addObject:@(cursor)];
    }

    NSMutableArray<NSDictionary *> *out = [NSMutableArray array];
    for (NSDictionary *diagnostic in diagnostics) {
        if (![diagnostic isKindOfClass:[NSDictionary class]]) continue;
        NSInteger line = [diagnostic[@"line"] integerValue];
        if (line < 1 || (NSUInteger)line > lineStarts.count) continue;
        NSInteger endLine = [diagnostic[@"endLine"] integerValue];
        if (endLine < line) endLine = line;
        if (endLine > (NSInteger)lineStarts.count) endLine = (NSInteger)lineStarts.count;

        NSUInteger location = MIN([self offsetForLine:line column:diagnostic[@"column"] lineStarts:lineStarts textLength:length], length);
        NSUInteger end = MIN([self offsetForLine:endLine column:diagnostic[@"endColumn"] lineStarts:lineStarts textLength:length], length);
        if (end <= location) end = MIN(location + 1, length);
        if (end <= location) end = location; // empty source at EOF
        [out addObject:@{
            @"range": [NSValue valueWithRange:NSMakeRange(location, end - location)],
            @"severity": diagnostic[@"severity"] ?: @"error",
            @"message": diagnostic[@"message"] ?: @"",
            @"code": diagnostic[@"code"] ?: @"",
            @"line": @(line),
        }];
    }
    return out;
}

@end
