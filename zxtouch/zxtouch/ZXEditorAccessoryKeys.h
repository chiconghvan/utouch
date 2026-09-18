//
//  ZXEditorAccessoryKeys.h
//  zxtouch
//
//  Catalog + persistence helpers for the extra-keys pane docked at the
//  bottom of the native script editor (one shared layout for all languages).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Key identifiers. Action keys (no insert text): esc, shift_tab,
// arrow_*, home, end, backspace, comment, del_line. Everything else inserts
// its text (tab inserts "\t" so the editor's Tab-to-spaces rule applies).
#define ZXEditorKeyEsc @"esc"
#define ZXEditorKeyTab @"tab"
#define ZXEditorKeyShiftTab @"shift_tab"
#define ZXEditorKeyLeft @"arrow_left"
#define ZXEditorKeyRight @"arrow_right"
#define ZXEditorKeyUp @"arrow_up"
#define ZXEditorKeyDown @"arrow_down"
#define ZXEditorKeyHome @"home"
#define ZXEditorKeyEnd @"end"
#define ZXEditorKeyLParen @"lparen"
#define ZXEditorKeyRParen @"rparen"
#define ZXEditorKeyLBracket @"lbracket"
#define ZXEditorKeyRBracket @"rbracket"
#define ZXEditorKeyLBrace @"lbrace"
#define ZXEditorKeyRBrace @"rbrace"
#define ZXEditorKeyColon @"colon"
#define ZXEditorKeySemicolon @"semicolon"
#define ZXEditorKeyComma @"comma"
#define ZXEditorKeyDot @"dot"
#define ZXEditorKeyEquals @"equals"
#define ZXEditorKeyDQuote @"dquote"
#define ZXEditorKeySQuote @"squote"
#define ZXEditorKeyUnderscore @"underscore"
#define ZXEditorKeyHash @"hash"
#define ZXEditorKeyPlus @"plus"
#define ZXEditorKeyMinus @"minus"
#define ZXEditorKeyStar @"star"
#define ZXEditorKeySlash @"slash"
#define ZXEditorKeyPercent @"percent"
#define ZXEditorKeyBackslash @"backslash"
#define ZXEditorKeyPipe @"pipe"
#define ZXEditorKeyComment @"comment"
#define ZXEditorKeyDeleteLine @"del_line"
#define ZXEditorKeyBackspace @"backspace"

@interface ZXEditorAccessoryKeys : NSObject

/// Every known identifier in catalog order.
+ (NSArray<NSString *> *)catalogIdentifiers;

/// Enabled identifiers for a fresh install (full ~20-key bar).
+ (NSArray<NSString *> *)defaultEnabledIdentifiers;

/// Display title for a button (e.g. @"<-", @"Tab", @"Esc").
+ (NSString *)titleForIdentifier:(NSString *)identifier;

/// Text to insert, or nil for action keys handled by the editor.
+ (nullable NSString *)insertTextForIdentifier:(NSString *)identifier;

/// YES for keys that should repeat while held (arrows, backspace).
+ (BOOL)isRepeatableIdentifier:(NSString *)identifier;

/// Enabled identifiers (in order) from the stored plist value.
/// Unknown/duplicate entries are dropped; nil returns the defaults.
+ (NSArray<NSString *> *)enabledIdentifiersFromStored:(nullable id)stored;

/// Full display order for Settings: enabled identifiers first (stored
/// order), then the remaining catalog identifiers appended.
+ (NSArray<NSString *> *)displayOrderFromStored:(nullable id)stored;

@end

NS_ASSUME_NONNULL_END
