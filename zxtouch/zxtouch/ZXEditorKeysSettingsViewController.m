//
//  ZXEditorKeysSettingsViewController.m
//  zxtouch
//

#import "ZXEditorKeysSettingsViewController.h"
#import "Config.h"
#import "ConfigManager.h"
#import "ZXEditorAccessoryKeys.h"
#import <objc/runtime.h>

@implementation ZXEditorKeysSettingsViewController {
    ConfigManager *_configManager;
    NSMutableArray<NSString *> *_orderedIdentifiers;
    NSMutableSet<NSString *> *_enabledIdentifiers;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Extra Keys";
    // Reorder handles come from edit mode; selection stays enabled so a row
    // tap can also flip its switch.
    self.tableView.editing = YES;
    self.tableView.allowsSelectionDuringEditing = YES;
    self.tableView.rowHeight = 52.0;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Reset"
                style:UIBarButtonItemStylePlain
               target:self
               action:@selector(resetToDefaults)];
    [self reloadModel];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadModel];
}

#pragma mark - Model

- (void)reloadModel {
    _configManager = [[ConfigManager alloc] initWithPath:SPRINGBOARD_CONFIG_PATH];
    id stored = [_configManager getValueFromKey:ZX_EDITOR_EXTRA_KEYS_KEY];
    _orderedIdentifiers = [[ZXEditorAccessoryKeys displayOrderFromStored:stored] mutableCopy];
    _enabledIdentifiers = [NSMutableSet setWithArray:
        [ZXEditorAccessoryKeys enabledIdentifiersFromStored:stored]];
    [self.tableView reloadData];
}

- (void)save {
    NSMutableArray<NSString *> *enabledInOrder = [NSMutableArray array];
    for (NSString *identifier in _orderedIdentifiers) {
        if ([_enabledIdentifiers containsObject:identifier]) [enabledInOrder addObject:identifier];
    }
    [_configManager updateKey:ZX_EDITOR_EXTRA_KEYS_KEY forValue:enabledInOrder];
    [_configManager save];
    // Any editor already on screen rebuilds its pane live.
    [[NSNotificationCenter defaultCenter]
        postNotificationName:ZX_EDITOR_EXTRA_KEYS_CHANGED_NOTIFICATION object:nil];
}

- (void)resetToDefaults {
    // Fresh-install order: defaults first, remaining catalog keys follow.
    _orderedIdentifiers = [[ZXEditorAccessoryKeys displayOrderFromStored:
        [ZXEditorAccessoryKeys defaultEnabledIdentifiers]] mutableCopy];
    _enabledIdentifiers = [NSMutableSet setWithArray:
        [ZXEditorAccessoryKeys defaultEnabledIdentifiers]];
    [self save];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _orderedIdentifiers.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Drag the handle to reorder. The editor bar shows the enabled keys "
           @"in this order; scroll it horizontally for the rest.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView
         cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"ExtraKeyCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                      reuseIdentifier:cellID];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.textLabel.font = [UIFont monospacedSystemFontOfSize:16.0
                                                          weight:UIFontWeightMedium];
        UISwitch *toggle = [[UISwitch alloc] init];
        [toggle addTarget:self
                   action:@selector(handleToggle:)
         forControlEvents:UIControlEventValueChanged];
        cell.editingAccessoryView = toggle;
    }
    NSString *identifier = _orderedIdentifiers[indexPath.row];
    cell.textLabel.text = [ZXEditorAccessoryKeys titleForIdentifier:identifier];
    UISwitch *toggle = (UISwitch *)cell.editingAccessoryView;
    toggle.on = [_enabledIdentifiers containsObject:identifier];
    objc_setAssociatedObject(toggle, @selector(handleToggle:), identifier, OBJC_ASSOCIATION_COPY_NONATOMIC);
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView
           editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath {
    // Reorder handles only, no delete/insert controls.
    return UITableViewCellEditingStyleNone;
}

- (BOOL)tableView:(UITableView *)tableView
shouldIndentWhileEditingRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView
moveRowAtIndexPath:(NSIndexPath *)sourceIndexPath
      toIndexPath:(NSIndexPath *)destinationIndexPath {
    NSString *identifier = _orderedIdentifiers[sourceIndexPath.row];
    [_orderedIdentifiers removeObjectAtIndex:sourceIndexPath.row];
    [_orderedIdentifiers insertObject:identifier atIndex:destinationIndexPath.row];
    [self save];
}

- (void)tableView:(UITableView *)tableView
didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *identifier = _orderedIdentifiers[indexPath.row];
    if ([_enabledIdentifiers containsObject:identifier]) {
        [_enabledIdentifiers removeObject:identifier];
    } else {
        [_enabledIdentifiers addObject:identifier];
    }
    [self save];
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    ((UISwitch *)cell.editingAccessoryView).on = [_enabledIdentifiers containsObject:identifier];
}

#pragma mark - Switch

- (void)handleToggle:(UISwitch *)toggle {
    NSString *identifier = objc_getAssociatedObject(toggle, @selector(handleToggle:));
    if (!identifier) return;
    if (toggle.isOn) [_enabledIdentifiers addObject:identifier];
    else [_enabledIdentifiers removeObject:identifier];
    [self save];
}

@end
