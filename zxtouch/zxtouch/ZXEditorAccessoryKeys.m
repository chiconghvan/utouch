//
//  ZXEditorAccessoryKeys.m
//  zxtouch
//

#import "ZXEditorAccessoryKeys.h"

@implementation ZXEditorAccessoryKeys

+ (NSArray<NSString *> *)catalogIdentifiers {
    static NSArray<NSString *> *catalog;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        catalog = @[
            ZXEditorKeyEsc,
            ZXEditorKeyTab, ZXEditorKeyShiftTab,
            ZXEditorKeyLeft, ZXEditorKeyRight, ZXEditorKeyUp, ZXEditorKeyDown,
            ZXEditorKeyHome, ZXEditorKeyEnd,
            ZXEditorKeyLParen, ZXEditorKeyRParen,
            ZXEditorKeyLBracket, ZXEditorKeyRBracket,
            ZXEditorKeyLBrace, ZXEditorKeyRBrace,
            ZXEditorKeyColon, ZXEditorKeySemicolon, ZXEditorKeyComma, ZXEditorKeyDot,
            ZXEditorKeyEquals,
            ZXEditorKeyDQuote, ZXEditorKeySQuote,
            ZXEditorKeyUnderscore, ZXEditorKeyHash,
            ZXEditorKeyPlus, ZXEditorKeyMinus, ZXEditorKeyStar, ZXEditorKeySlash,
            ZXEditorKeyPercent, ZXEditorKeyBackslash, ZXEditorKeyPipe,
            ZXEditorKeyComment, ZXEditorKeyDeleteLine,
            ZXEditorKeyBackspace,
        ];
    });
    return catalog;
}

+ (NSArray<NSString *> *)defaultEnabledIdentifiers {
    // Full default bar: navigation + indent + the brackets/symbols needed
    // for Python/Lua without switching iOS keyboards.
    return @[
        ZXEditorKeyEsc,
        ZXEditorKeyTab, ZXEditorKeyShiftTab,
        ZXEditorKeyLeft, ZXEditorKeyRight, ZXEditorKeyUp, ZXEditorKeyDown,
        ZXEditorKeyHome, ZXEditorKeyEnd,
        ZXEditorKeyLParen, ZXEditorKeyRParen,
        ZXEditorKeyLBracket, ZXEditorKeyRBracket,
        ZXEditorKeyLBrace, ZXEditorKeyRBrace,
        ZXEditorKeyColon, ZXEditorKeyEquals,
        ZXEditorKeyDQuote, ZXEditorKeySQuote,
        ZXEditorKeyUnderscore, ZXEditorKeyHash,
        ZXEditorKeyBackspace,
    ];
}

+ (NSString *)titleForIdentifier:(NSString *)identifier {
    static NSDictionary<NSString *, NSString *> *titles;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = @{
            ZXEditorKeyEsc: @"Esc",
            ZXEditorKeyTab: @"Tab",
            ZXEditorKeyShiftTab: @"⇧Tab",
            ZXEditorKeyLeft: @"←",
            ZXEditorKeyRight: @"→",
            ZXEditorKeyUp: @"↑",
            ZXEditorKeyDown: @"↓",
            ZXEditorKeyHome: @"Home",
            ZXEditorKeyEnd: @"End",
            ZXEditorKeyLParen: @"(",
            ZXEditorKeyRParen: @")",
            ZXEditorKeyLBracket: @"[",
            ZXEditorKeyRBracket: @"]",
            ZXEditorKeyLBrace: @"{",
            ZXEditorKeyRBrace: @"}",
            ZXEditorKeyColon: @":",
            ZXEditorKeySemicolon: @";",
            ZXEditorKeyComma: @",",
            ZXEditorKeyDot: @".",
            ZXEditorKeyEquals: @"=",
            ZXEditorKeyDQuote: @"\"",
            ZXEditorKeySQuote: @"'",
            ZXEditorKeyUnderscore: @"_",
            ZXEditorKeyHash: @"#",
            ZXEditorKeyPlus: @"+",
            ZXEditorKeyMinus: @"-",
            ZXEditorKeyStar: @"*",
            ZXEditorKeySlash: @"/",
            ZXEditorKeyPercent: @"%",
            ZXEditorKeyBackslash: @"\\",
            ZXEditorKeyPipe: @"|",
            ZXEditorKeyComment: @"#--",
            ZXEditorKeyDeleteLine: @"⌦",
            ZXEditorKeyBackspace: @"⌫",
        };
    });
    NSString *title = titles[identifier];
    return title ?: identifier;
}

+ (nullable NSString *)insertTextForIdentifier:(NSString *)identifier {
    static NSDictionary<NSString *, NSString *> *inserts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        inserts = @{
            ZXEditorKeyTab: @"\t",
            ZXEditorKeyLParen: @"(",
            ZXEditorKeyRParen: @")",
            ZXEditorKeyLBracket: @"[",
            ZXEditorKeyRBracket: @"]",
            ZXEditorKeyLBrace: @"{",
            ZXEditorKeyRBrace: @"}",
            ZXEditorKeyColon: @":",
            ZXEditorKeySemicolon: @";",
            ZXEditorKeyComma: @",",
            ZXEditorKeyDot: @".",
            ZXEditorKeyEquals: @"=",
            ZXEditorKeyDQuote: @"\"",
            ZXEditorKeySQuote: @"'",
            ZXEditorKeyUnderscore: @"_",
            ZXEditorKeyHash: @"#",
            ZXEditorKeyPlus: @"+",
            ZXEditorKeyMinus: @"-",
            ZXEditorKeyStar: @"*",
            ZXEditorKeySlash: @"/",
            ZXEditorKeyPercent: @"%",
            ZXEditorKeyBackslash: @"\\",
            ZXEditorKeyPipe: @"|",
        };
    });
    return inserts[identifier];
}

+ (BOOL)isRepeatableIdentifier:(NSString *)identifier {
    return [identifier isEqualToString:ZXEditorKeyLeft]
        || [identifier isEqualToString:ZXEditorKeyRight]
        || [identifier isEqualToString:ZXEditorKeyUp]
        || [identifier isEqualToString:ZXEditorKeyDown]
        || [identifier isEqualToString:ZXEditorKeyBackspace];
}

+ (NSArray<NSString *> *)enabledIdentifiersFromStored:(nullable id)stored {
    if (![stored isKindOfClass:[NSArray class]]) return [self defaultEnabledIdentifiers];
    NSSet<NSString *> *known = [NSSet setWithArray:[self catalogIdentifiers]];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    for (id entry in (NSArray *)stored) {
        if (![entry isKindOfClass:[NSString class]]) continue;
        if (![known containsObject:entry]) continue;
        if ([seen containsObject:entry]) continue;
        [seen addObject:entry];
        [result addObject:entry];
    }
    return [result copy];
}

+ (NSArray<NSString *> *)displayOrderFromStored:(nullable id)stored {
    NSArray<NSString *> *enabled = [self enabledIdentifiersFromStored:stored];
    // A missing value means fresh install: show exactly the defaults.
    if (stored == nil || stored == [NSNull null]) return enabled;
    NSMutableArray<NSString *> *display = [enabled mutableCopy];
    NSSet<NSString *> *enabledSet = [NSSet setWithArray:enabled];
    for (NSString *identifier in [self catalogIdentifiers]) {
        if (![enabledSet containsObject:identifier]) [display addObject:identifier];
    }
    return [display copy];
}

@end
