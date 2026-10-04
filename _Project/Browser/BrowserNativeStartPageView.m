#import "BrowserNativeStartPageView.h"

#import "BrowserTVAppearance.h"

@interface BrowserNativeStartPageView () <UITableViewDataSource, UITableViewDelegate>
@property (nonatomic) UITableView *tableView;
@property (nonatomic, copy) NSArray<NSDictionary *> *favorites;
@property (nonatomic, copy) NSArray<NSDictionary *> *recents;
@property (nonatomic) NSIndexPath *selectedIndexPath;
@end

@implementation BrowserNativeStartPageView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    BrowserTVInstallBackground(self);

    UILabel *heading = [UILabel new];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.text = @"New Tab";
    heading.textColor = UIColor.whiteColor;
    heading.font = [UIFont systemFontOfSize:58 weight:UIFontWeightBold];
    [self addSubview:heading];

    UITableView *table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    table.translatesAutoresizingMaskIntoConstraints = NO;
    table.backgroundColor = UIColor.clearColor;
    table.rowHeight = 86;
    table.estimatedSectionHeaderHeight = 48;
    table.sectionHeaderHeight = 48;
    table.dataSource = self;
    table.delegate = self;
    table.showsVerticalScrollIndicator = YES;
    [self addSubview:table];
    self.tableView = table;

    [NSLayoutConstraint activateConstraints:@[
        [heading.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:42],
        [heading.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:24],
        [table.leadingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.leadingAnchor constant:42],
        [table.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-42],
        [table.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:18],
        [table.bottomAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.bottomAnchor constant:-20],
    ]];
    self.selectedIndexPath = [NSIndexPath indexPathForRow:0 inSection:0];
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    BrowserTVLayoutBackground(self);
}

- (void)reloadFavorites:(NSArray<NSArray<NSString *> *> *)favorites
                recents:(NSArray<NSDictionary *> *)recents
         selectingGroup:(NSString *)group
                  index:(NSUInteger)index {
    NSMutableArray *validFavorites = [NSMutableArray array];
    for (NSUInteger storageIndex = 0; storageIndex < favorites.count && validFavorites.count < 40; storageIndex++) {
        NSArray *entry = favorites[storageIndex];
        NSString *URLString = entry.count > 0 && [entry[0] isKindOfClass:NSString.class] ? entry[0] : @"";
        NSURL *URL = [NSURL URLWithString:URLString];
        if (URL.host.length == 0 || ![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString]) continue;
        [validFavorites addObject:@{ @"entry": entry, @"storageIndex": @(storageIndex) }];
    }
    self.favorites = [validFavorites copy];
    self.recents = [recents subarrayWithRange:NSMakeRange(0, MIN(recents.count, 10))];
    [self.tableView reloadData];

    NSInteger section = [group isEqualToString:@"favorites"] ? 1 : [group isEqualToString:@"history"] ? 2 : 0;
    NSInteger row = MIN((NSInteger)index, [self tableView:self.tableView numberOfRowsInSection:section] - 1);
    self.selectedIndexPath = [NSIndexPath indexPathForRow:MAX(0, row) inSection:section];
    [self.tableView scrollToRowAtIndexPath:self.selectedIndexPath atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
    [self refreshVisibleRows];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return MAX(1, (NSInteger)self.favorites.count);
        case 2: return MAX(1, (NSInteger)self.recents.count);
        default: return 1;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 1: return @"FAVORITES";
        case 2: return @"RECENTS";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"StartPageRow"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"StartPageRow"];
        cell.backgroundColor = UIColor.clearColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.focusStyle = UITableViewCellFocusStyleCustom;
        cell.contentView.layer.cornerRadius = 28;
        cell.contentView.layer.masksToBounds = YES;
        cell.textLabel.font = [UIFont systemFontOfSize:28 weight:UIFontWeightMedium];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:19];
        cell.imageView.tintColor = UIColor.whiteColor;
    }
    NSString *title = @"";
    NSString *detail = @"";
    NSString *symbol = @"chevron.right";
    if (path.section == 0) {
        title = @"Search or enter an address";
        symbol = @"magnifyingglass";
    } else if (path.section == 1 && self.favorites.count > 0) {
        NSDictionary *item = self.favorites[(NSUInteger)path.row];
        NSArray *entry = item[@"entry"];
        NSString *URLString = entry[0];
        NSString *storedTitle = entry.count > 1 && [entry[1] isKindOfClass:NSString.class] ? entry[1] : @"";
        title = storedTitle.length ? storedTitle : [NSURL URLWithString:URLString].host;
        detail = URLString;
        symbol = @"star.fill";
    } else if (path.section == 2 && self.recents.count > 0) {
        NSDictionary *entry = self.recents[(NSUInteger)path.row];
        NSString *URLString = entry[@"url"] ?: @"";
        title = [entry[@"title"] length] ? entry[@"title"] : [NSURL URLWithString:URLString].host;
        detail = URLString;
        symbol = @"clock.arrow.circlepath";
    } else if (path.section == 3) {
        title = @"All History";
        symbol = @"clock";
    } else {
        title = path.section == 1 ? @"Saved pages will appear here" : @"Visited pages will appear here";
        symbol = @"circle.dashed";
    }
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    cell.imageView.image = [UIImage systemImageNamed:symbol];
    [self styleCell:cell atIndexPath:path];
    return cell;
}

- (void)styleCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)path {
    BOOL selected = [path isEqual:self.selectedIndexPath];
    cell.contentView.backgroundColor = selected ? BrowserTVFocusedSurfaceColor() : BrowserTVRestingSurfaceColor();
    cell.textLabel.textColor = selected ? BrowserTVFocusedTextColor() : UIColor.whiteColor;
    cell.detailTextLabel.textColor = selected ? BrowserTVFocusedTextColor() : [UIColor colorWithWhite:1 alpha:0.7];
    cell.imageView.tintColor = selected ? BrowserTVFocusedTextColor() : UIColor.whiteColor;
}

- (void)refreshVisibleRows {
    [UIView animateWithDuration:0.22 animations:^{
        for (UITableViewCell *cell in self.tableView.visibleCells) {
            NSIndexPath *path = [self.tableView indexPathForCell:cell];
            if (path) [self styleCell:cell atIndexPath:path];
        }
    }];
}

- (void)selectIndexPath:(NSIndexPath *)path {
    if (!path) return;
    self.selectedIndexPath = path;
    [self.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:YES];
    [self refreshVisibleRows];
}

- (void)navigateInDirection:(NSString *)direction {
    NSInteger section = self.selectedIndexPath.section;
    NSInteger row = self.selectedIndexPath.row;
    if ([direction isEqualToString:@"up"] || [direction isEqualToString:@"left"]) {
        if (row > 0) row--;
        else if (section > 0) { section--; row = [self tableView:self.tableView numberOfRowsInSection:section] - 1; }
    } else if ([direction isEqualToString:@"down"] || [direction isEqualToString:@"right"]) {
        if (row + 1 < [self tableView:self.tableView numberOfRowsInSection:section]) row++;
        else if (section < 3) { section++; row = 0; }
    }
    [self selectIndexPath:[NSIndexPath indexPathForRow:row inSection:section]];
}

- (void)activateSelection { [self activateIndexPath:self.selectedIndexPath]; }

- (void)activateAtPoint:(CGPoint)point {
    CGPoint tablePoint = [self convertPoint:point toView:self.tableView];
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:tablePoint];
    if (path) { [self selectIndexPath:path]; [self activateIndexPath:path]; }
}

- (void)activateIndexPath:(NSIndexPath *)path {
    if (!path) return;
    if (path.section == 0) { if (self.openSearch) self.openSearch(); return; }
    if (path.section == 1 && self.favorites.count > 0) {
        NSArray *entry = self.favorites[(NSUInteger)path.row][@"entry"];
        if (self.openURLString) self.openURLString(entry[0]);
    } else if (path.section == 2 && self.recents.count > 0) {
        if (self.openURLString) self.openURLString(self.recents[(NSUInteger)path.row][@"url"]);
    } else if (path.section == 3 && self.showAllHistory) self.showAllHistory();
}

- (void)showOptionForSelection { [self showOptionAtIndexPath:self.selectedIndexPath]; }

- (void)showOptionAtPoint:(CGPoint)point {
    CGPoint tablePoint = [self convertPoint:point toView:self.tableView];
    NSIndexPath *path = [self.tableView indexPathForRowAtPoint:tablePoint];
    if (path) { [self selectIndexPath:path]; [self showOptionAtIndexPath:path]; }
}

- (void)showOptionAtIndexPath:(NSIndexPath *)path {
    if (path.section == 1 && self.favorites.count > 0 && self.manageFavorite) {
        NSDictionary *item = self.favorites[(NSUInteger)path.row];
        self.manageFavorite([item[@"storageIndex"] unsignedIntegerValue]);
    } else if (path.section == 2 && self.recents.count > 0 && self.deleteRecentVisit) {
        self.deleteRecentVisit(self.recents[(NSUInteger)path.row][@"url"]);
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [self selectIndexPath:path];
    [self activateIndexPath:path];
}

- (BOOL)tableView:(UITableView *)tableView canFocusRowAtIndexPath:(NSIndexPath *)indexPath {
    // RemoteInputController already owns directional selection on the start page.
    // A second UIKit focus target would leave two rows looking active.
    return NO;
}

@end
