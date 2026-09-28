#import "BrowserHistoryViewController.h"
#import "BrowserHistoryStore.h"

@interface BrowserHistoryButton : UIButton
@property (nonatomic, strong) UIColor *restingColor;
@end

@implementation BrowserHistoryButton
- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        self.backgroundColor = self.isFocused ? [UIColor colorWithWhite:0.96 alpha:0.98] : self.restingColor;
        [self setTitleColor:self.isFocused ? [UIColor colorWithRed:0.10 green:0.15 blue:0.25 alpha:1.0]
                                           : UIColor.whiteColor forState:UIControlStateNormal];
    } completion:nil];
}
@end

@interface BrowserHistoryCell : UITableViewCell
@property (nonatomic) BOOL checked;
- (void)refreshAppearance;
@end

@implementation BrowserHistoryCell

- (void)refreshAppearance {
    BOOL focused = self.isFocused;
    self.contentView.backgroundColor = focused ? [UIColor colorWithWhite:0.95 alpha:0.94]
                                               : [UIColor colorWithWhite:1.0 alpha:0.10];
    self.textLabel.textColor = focused ? [UIColor colorWithRed:0.10 green:0.15 blue:0.24 alpha:1.0] : UIColor.whiteColor;
    self.detailTextLabel.textColor = focused ? [UIColor colorWithRed:0.29 green:0.34 blue:0.43 alpha:1.0]
                                             : [UIColor colorWithWhite:1.0 alpha:0.68];
    self.accessoryView.tintColor = self.checked
        ? (focused ? [UIColor colorWithRed:0.13 green:0.34 blue:0.75 alpha:1.0]
                   : [UIColor colorWithRed:0.58 green:0.74 blue:1.0 alpha:1.0])
        : (focused ? [UIColor colorWithRed:0.32 green:0.38 blue:0.48 alpha:1.0]
                   : [UIColor colorWithWhite:1.0 alpha:0.65]);
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{ [self refreshAppearance]; } completion:nil];
}

@end

@interface BrowserHistoryViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSArray<NSDictionary *> *entries;
@property (nonatomic, strong) NSMutableIndexSet *selectedIndexes;
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UIButton *selectAllButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *doneButton;
@property (nonatomic, strong) UILabel *countLabel;
@property (nonatomic, strong) CAGradientLayer *backgroundGradient;

@end

@implementation BrowserHistoryViewController

- (instancetype)init {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _selectedIndexes = [NSMutableIndexSet indexSet];
    }
    return self;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight color:(UIColor *)color {
    UILabel *label = [UILabel new];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textColor = color;
    return label;
}

- (UIButton *)button:(NSString *)title color:(UIColor *)color selector:(SEL)selector {
    BrowserHistoryButton *button = [BrowserHistoryButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.restingColor = color;
    button.backgroundColor = color;
    button.layer.cornerRadius = 18.0;
    button.titleLabel.font = [UIFont systemFontOfSize:27.0 weight:UIFontWeightSemibold];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [button addTarget:self action:selector forControlEvents:UIControlEventPrimaryActionTriggered];
    return button;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.07 green:0.10 blue:0.17 alpha:1.0];
    CAGradientLayer *gradient = [CAGradientLayer layer];
    gradient.colors = @[(id)[UIColor colorWithRed:0.19 green:0.28 blue:0.43 alpha:1.0].CGColor,
                        (id)[UIColor colorWithRed:0.16 green:0.15 blue:0.28 alpha:1.0].CGColor,
                        (id)[UIColor colorWithRed:0.08 green:0.10 blue:0.17 alpha:1.0].CGColor];
    gradient.startPoint = CGPointMake(0.0, 0.0);
    gradient.endPoint = CGPointMake(1.0, 1.0);
    [self.view.layer addSublayer:gradient];
    self.backgroundGradient = gradient;
    self.entries = [[BrowserHistoryStore sharedStore] allVisits];

    UILabel *eyebrow = [self label:@"BROWSER" size:23.0 weight:UIFontWeightBold
                              color:[UIColor colorWithRed:0.58 green:0.72 blue:1.0 alpha:1.0]];
    UILabel *heading = [self label:@"All History" size:62.0 weight:UIFontWeightBold color:UIColor.whiteColor];
    UILabel *countLabel = [self label:@"" size:26.0 weight:UIFontWeightRegular
                                color:[UIColor colorWithWhite:1.0 alpha:0.58]];
    self.countLabel = countLabel;
    [self.view addSubview:eyebrow];
    [self.view addSubview:heading];
    [self.view addSubview:countLabel];

    Class glassClass = NSClassFromString(@"UIGlassEffect");
    UIVisualEffect *effect = glassClass != Nil ? [[glassClass alloc] init]
                                              : [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    UIVisualEffectView *glassPanel = [[UIVisualEffectView alloc] initWithEffect:effect];
    glassPanel.translatesAutoresizingMaskIntoConstraints = NO;
    glassPanel.layer.cornerRadius = 30.0;
    glassPanel.layer.masksToBounds = YES;
    glassPanel.layer.borderWidth = glassClass != Nil ? 0.0 : 1.0;
    glassPanel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    [self.view addSubview:glassPanel];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.dataSource = self;
    table.delegate = self;
    table.rowHeight = 90.0;
    table.backgroundColor = UIColor.clearColor;
    table.showsVerticalScrollIndicator = YES;
    [self.view addSubview:table];
    self.tableView = table;

    UIButton *selectAll = [self button:@"Select All" color:[UIColor colorWithWhite:1.0 alpha:0.16]
                                 selector:@selector(selectAllPressed)];
    UIButton *remove = [self button:@"Delete Selected" color:[UIColor colorWithRed:0.65 green:0.24 blue:0.33 alpha:0.72]
                              selector:@selector(deletePressed)];
    UIButton *done = [self button:@"Done" color:[UIColor colorWithRed:0.28 green:0.50 blue:0.92 alpha:0.65]
                            selector:@selector(donePressed)];
    [self.view addSubview:selectAll];
    [self.view addSubview:remove];
    [self.view addSubview:done];
    self.selectAllButton = selectAll;
    self.deleteButton = remove;
    self.doneButton = done;

    [NSLayoutConstraint activateConstraints:@[
        [eyebrow.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:110.0],
        [eyebrow.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:70.0],
        [heading.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [heading.topAnchor constraintEqualToAnchor:eyebrow.bottomAnchor constant:8.0],
        [countLabel.leadingAnchor constraintEqualToAnchor:eyebrow.leadingAnchor],
        [countLabel.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:6.0],
        [table.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:110.0],
        [table.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-110.0],
        [table.topAnchor constraintEqualToAnchor:countLabel.bottomAnchor constant:34.0],
        [table.bottomAnchor constraintEqualToAnchor:selectAll.topAnchor constant:-28.0],
        [glassPanel.leadingAnchor constraintEqualToAnchor:table.leadingAnchor constant:-14.0],
        [glassPanel.trailingAnchor constraintEqualToAnchor:table.trailingAnchor constant:14.0],
        [glassPanel.topAnchor constraintEqualToAnchor:table.topAnchor constant:-14.0],
        [glassPanel.bottomAnchor constraintEqualToAnchor:table.bottomAnchor constant:14.0],
        [selectAll.leadingAnchor constraintEqualToAnchor:table.leadingAnchor],
        [selectAll.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-70.0],
        [selectAll.widthAnchor constraintEqualToConstant:245.0],
        [selectAll.heightAnchor constraintEqualToConstant:68.0],
        [remove.leadingAnchor constraintEqualToAnchor:selectAll.trailingAnchor constant:20.0],
        [remove.centerYAnchor constraintEqualToAnchor:selectAll.centerYAnchor],
        [remove.widthAnchor constraintEqualToConstant:295.0],
        [remove.heightAnchor constraintEqualToConstant:68.0],
        [done.trailingAnchor constraintEqualToAnchor:table.trailingAnchor],
        [done.centerYAnchor constraintEqualToAnchor:selectAll.centerYAnchor],
        [done.widthAnchor constraintEqualToConstant:200.0],
        [done.heightAnchor constraintEqualToConstant:68.0],
    ]];
    [self updateActions];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.backgroundGradient.frame = self.view.bounds;
}

- (void)updateActions {
    self.countLabel.text = [NSString stringWithFormat:@"%lu visited pages · %lu selected",
                            (unsigned long)self.entries.count, (unsigned long)self.selectedIndexes.count];
    self.deleteButton.enabled = self.selectedIndexes.count > 0;
    self.deleteButton.alpha = self.deleteButton.enabled ? 1.0 : 0.45;
    [self.selectAllButton setTitle:self.selectedIndexes.count == self.entries.count && self.entries.count > 0
                                    ? @"Deselect All" : @"Select All" forState:UIControlStateNormal];
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(__unused NSInteger)section {
    return (NSInteger)self.entries.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    BrowserHistoryCell *cell = [tableView dequeueReusableCellWithIdentifier:@"HistoryEntry"];
    if (cell == nil) {
        cell = [[BrowserHistoryCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"HistoryEntry"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.focusStyle = UITableViewCellFocusStyleCustom;
        cell.contentView.layer.cornerRadius = 18.0;
        cell.contentView.layer.masksToBounds = YES;
        cell.textLabel.font = [UIFont systemFontOfSize:28.0 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightRegular];
    }
    NSDictionary *entry = self.entries[(NSUInteger)indexPath.row];
    NSString *URLString = entry[@"url"] ?: @"";
    NSString *title = entry[@"title"] ?: @"";
    cell.textLabel.text = title.length > 0 ? title : URLString;
    cell.detailTextLabel.text = URLString;
    UIImageView *check = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:
        [self.selectedIndexes containsIndex:(NSUInteger)indexPath.row] ? @"checkmark.square.fill" : @"square"]];
    check.contentMode = UIViewContentModeScaleAspectFit;
    check.frame = CGRectMake(0.0, 0.0, 38.0, 38.0);
    cell.accessoryView = check;
    cell.checked = [self.selectedIndexes containsIndex:(NSUInteger)indexPath.row];
    [cell refreshAppearance];
    cell.accessibilityValue = [self.selectedIndexes containsIndex:(NSUInteger)indexPath.row] ? @"Selected" : @"Not selected";
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSUInteger index = (NSUInteger)indexPath.row;
    if ([self.selectedIndexes containsIndex:index]) {
        [self.selectedIndexes removeIndex:index];
    } else {
        [self.selectedIndexes addIndex:index];
    }
    [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
    [self updateActions];
}

- (void)selectAllPressed {
    if (self.selectedIndexes.count == self.entries.count) {
        [self.selectedIndexes removeAllIndexes];
    } else {
        [self.selectedIndexes addIndexesInRange:NSMakeRange(0, self.entries.count)];
    }
    [self.tableView reloadData];
    [self updateActions];
}

- (void)deletePressed {
    if (self.selectedIndexes.count == 0) {
        return;
    }
    NSMutableArray<NSNumber *> *identifiers = [NSMutableArray array];
    [self.selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger index, __unused BOOL *stop) {
        if (index < self.entries.count) [identifiers addObject:self.entries[index][@"id"]];
    }];
    [[BrowserHistoryStore sharedStore] deleteVisitsWithIdentifiers:identifiers];
    self.entries = [[BrowserHistoryStore sharedStore] allVisits];
    [self.selectedIndexes removeAllIndexes];
    [self.tableView reloadData];
    [self updateActions];
    if (self.historyDidChange != nil) {
        self.historyDidChange();
    }
}

- (void)donePressed {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    return self.entries.count > 0 ? @[self.tableView] : @[self.doneButton];
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    for (UIPress *press in presses) {
        if (press.type == UIPressTypeMenu) {
            [self donePressed];
            return;
        }
    }
    [super pressesEnded:presses withEvent:event];
}

@end
