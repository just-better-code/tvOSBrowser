#import "BrowserMenuCoordinator.h"
#import "BrowserPreferencesStore.h"
#import "BrowserWebView.h"

static UIColor *MenuTextColor(void) {
    if (@available(tvOS 13, *)) {
        return UIColor.labelColor;
    } else {
        return UIColor.blackColor;
    }
}

static NSString * const kBrowserMediaDiagnosticsLogPrefix = @"[MediaDiagnostics]";
static NSString * const kBrowserWebKitMediaPrefsLogPrefix = @"[WebKitMediaPrefs]";
static NSUInteger const kBrowserNavigationToolbarItemCount = 5;

typedef void (^BrowserAdvancedMenuItemHandler)(void);
typedef BOOL (^BrowserAdvancedMenuToggleStateProvider)(void);

@interface BrowserAdvancedMenuItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic) UIAlertActionStyle style;
@property (nonatomic, copy) BrowserAdvancedMenuItemHandler handler;
@property (nonatomic, copy) BrowserAdvancedMenuToggleStateProvider toggleStateProvider;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL keepsMenuOpen;

+ (instancetype)itemWithTitle:(NSString *)title
                        style:(UIAlertActionStyle)style
                      handler:(BrowserAdvancedMenuItemHandler)handler;

@end

@implementation BrowserAdvancedMenuItem

+ (instancetype)itemWithTitle:(NSString *)title
                        style:(UIAlertActionStyle)style
                      handler:(BrowserAdvancedMenuItemHandler)handler {
    BrowserAdvancedMenuItem *item = [BrowserAdvancedMenuItem new];
    item.title = title ?: @"";
    item.style = style;
    item.handler = handler;
    item.enabled = YES;
    return item;
}

@end

@interface BrowserAdvancedMenuSection : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSArray<BrowserAdvancedMenuItem *> *items;

+ (instancetype)sectionWithTitle:(NSString *)title items:(NSArray<BrowserAdvancedMenuItem *> *)items;

@end

@implementation BrowserAdvancedMenuSection

+ (instancetype)sectionWithTitle:(NSString *)title items:(NSArray<BrowserAdvancedMenuItem *> *)items {
    BrowserAdvancedMenuSection *section = [BrowserAdvancedMenuSection new];
    section.title = title ?: @"";
    section.items = [items copy] ?: @[];
    return section;
}

@end

@interface BrowserAdvancedMenuViewController : UIViewController <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSString *addressText;
@property (nonatomic, copy) BrowserAdvancedMenuItemHandler addressHandler;

- (instancetype)initWithToolbarItems:(NSArray<BrowserAdvancedMenuItem *> *)toolbarItems
                           sections:(NSArray<BrowserAdvancedMenuSection *> *)sections
                   footerText:(NSString *)footerText;

@end

@interface BrowserAdvancedMenuViewController ()

@property (nonatomic, copy) NSArray<BrowserAdvancedMenuItem *> *toolbarItems;
@property (nonatomic, copy) NSArray<UIButton *> *toolbarButtons;
@property (nonatomic) UIButton *addressButton;
@property (nonatomic, copy) NSArray<BrowserAdvancedMenuSection *> *sections;
@property (nonatomic, copy) NSString *footerText;
@property (nonatomic) UIView *dimView;
@property (nonatomic) UIVisualEffectView *panelView;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSLayoutConstraint *panelTrailingConstraint;
@property (nonatomic) CGFloat panelWidth;
@property (nonatomic) BOOL didAnimateIn;
@property (nonatomic) BOOL dismissalInProgress;
@property (nonatomic) BOOL usingNativeGlassEffect;

@end

@implementation BrowserAdvancedMenuViewController

- (UIVisualEffect *)panelEffect {
    Class glassEffectClass = NSClassFromString(@"UIGlassEffect");
    if (glassEffectClass != Nil) {
        id effect = [[glassEffectClass alloc] init];
        if ([effect isKindOfClass:[UIVisualEffect class]]) {
            return (UIVisualEffect *)effect;
        }
    }
    return [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
}

- (instancetype)initWithToolbarItems:(NSArray<BrowserAdvancedMenuItem *> *)toolbarItems
                           sections:(NSArray<BrowserAdvancedMenuSection *> *)sections
                   footerText:(NSString *)footerText {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _toolbarItems = [toolbarItems copy] ?: @[];
        _sections = [sections copy] ?: @[];
        _footerText = [footerText copy] ?: @"";
        self.modalPresentationStyle = UIModalPresentationOverCurrentContext;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.clearColor;

    self.panelWidth = MIN(MAX(CGRectGetWidth(UIScreen.mainScreen.bounds) * 0.38, 480.0), 700.0);
    self.usingNativeGlassEffect = (NSClassFromString(@"UIGlassEffect") != Nil);

    UIView *dimView = [UIView new];
    dimView.translatesAutoresizingMaskIntoConstraints = NO;
    dimView.backgroundColor = self.usingNativeGlassEffect ? UIColor.clearColor : [UIColor colorWithWhite:0.0 alpha:0.45];
    dimView.alpha = 0.0;
    [self.view addSubview:dimView];
    self.dimView = dimView;

    UIVisualEffectView *panelView = [[UIVisualEffectView alloc] initWithEffect:[self panelEffect]];
    panelView.translatesAutoresizingMaskIntoConstraints = NO;
    panelView.backgroundColor = UIColor.clearColor;
    panelView.layer.cornerRadius = 28.0;
    panelView.layer.masksToBounds = YES;
    panelView.layer.borderWidth = self.usingNativeGlassEffect ? 0.0 : 1.0;
    panelView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.28].CGColor;
    [self.view addSubview:panelView];
    self.panelView = panelView;

    UIView *panelTint = nil;
    if (!self.usingNativeGlassEffect) {
        panelTint = [UIView new];
        panelTint.translatesAutoresizingMaskIntoConstraints = NO;
        panelTint.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
        [panelView.contentView addSubview:panelTint];
    }

    UIButton *addressButton = [UIButton buttonWithType:UIButtonTypeSystem];
    addressButton.translatesAutoresizingMaskIntoConstraints = NO;
    addressButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12];
    addressButton.layer.cornerRadius = 16.0;
    addressButton.accessibilityLabel = @"Edit Address";
    addressButton.accessibilityValue = self.addressText;
    [addressButton addTarget:self action:@selector(addressButtonPressed:) forControlEvents:UIControlEventPrimaryActionTriggered];
    [panelView.contentView addSubview:addressButton];
    self.addressButton = addressButton;

    UIImageSymbolConfiguration *addressSymbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:28.0
                                                                                                              weight:UIImageSymbolWeightMedium];
    UIImageView *addressIcon = [[UIImageView alloc] initWithImage:[[UIImage systemImageNamed:@"globe" withConfiguration:addressSymbolConfiguration]
                                                                   imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
    addressIcon.translatesAutoresizingMaskIntoConstraints = NO;
    addressIcon.tag = 9797;
    addressIcon.tintColor = UIColor.whiteColor;
    addressIcon.userInteractionEnabled = NO;
    [addressButton addSubview:addressIcon];

    UILabel *addressLabel = [UILabel new];
    addressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    addressLabel.tag = 9898;
    addressLabel.text = self.addressText.length > 0 ? self.addressText : @"Search or enter address";
    addressLabel.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightMedium];
    addressLabel.textColor = UIColor.whiteColor;
    addressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    addressLabel.userInteractionEnabled = NO;
    [addressButton addSubview:addressLabel];

    UIStackView *navigationToolbar = [UIStackView new];
    UIStackView *quickToolbar = [UIStackView new];
    for (UIStackView *row in @[navigationToolbar, quickToolbar]) {
        row.translatesAutoresizingMaskIntoConstraints = NO;
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentFill;
        row.distribution = UIStackViewDistributionFillEqually;
        row.spacing = 8.0;
        [panelView.contentView addSubview:row];
    }
    NSArray<NSString *> *toolbarSymbols = @[@"house.fill", @"chevron.left", @"arrow.clockwise", @"chevron.right",
                                            @"square.on.square", @"star", @"clock.arrow.circlepath",
                                            @"minus.magnifyingglass", @"", @"plus.magnifyingglass"];
    NSMutableArray<UIButton *> *toolbarButtons = [NSMutableArray arrayWithCapacity:self.toolbarItems.count];
    [self.toolbarItems enumerateObjectsUsingBlock:^(BrowserAdvancedMenuItem *item, NSUInteger index, __unused BOOL *stop) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 10000 + (NSInteger)index;
        button.enabled = item.enabled;
        button.backgroundColor = item.toggleStateProvider != nil && item.toggleStateProvider()
            ? [UIColor colorWithRed:0.20 green:0.54 blue:0.90 alpha:0.72]
            : [UIColor colorWithWhite:1.0 alpha:0.12];
        button.layer.cornerRadius = 12.0;
        NSString *symbolName = index < toolbarSymbols.count ? toolbarSymbols[index] : @"";
        if (symbolName.length > 0) {
            UIImageSymbolConfiguration *symbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:34.0
                                                                                                               weight:UIImageSymbolWeightMedium];
            UIImage *symbol = [UIImage systemImageNamed:symbolName withConfiguration:symbolConfiguration];
            UIImageView *iconView = [[UIImageView alloc] initWithImage:[symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]];
            iconView.translatesAutoresizingMaskIntoConstraints = NO;
            iconView.tag = 9797;
            iconView.contentMode = UIViewContentModeScaleAspectFit;
            iconView.tintColor = UIColor.whiteColor;
            iconView.alpha = item.enabled ? 1.0 : 0.35;
            iconView.userInteractionEnabled = NO;
            [button addSubview:iconView];
            [NSLayoutConstraint activateConstraints:@[
                [iconView.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
                [iconView.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
                [iconView.widthAnchor constraintEqualToConstant:42.0],
                [iconView.heightAnchor constraintEqualToConstant:42.0],
            ]];
        } else {
            UILabel *iconLabel = [UILabel new];
            iconLabel.translatesAutoresizingMaskIntoConstraints = NO;
            iconLabel.tag = 9797;
            iconLabel.text = @"1:1";
            iconLabel.font = [UIFont systemFontOfSize:34.0 weight:UIFontWeightSemibold];
            iconLabel.textColor = UIColor.whiteColor;
            iconLabel.textAlignment = NSTextAlignmentCenter;
            iconLabel.userInteractionEnabled = NO;
            [button addSubview:iconLabel];
            [NSLayoutConstraint activateConstraints:@[
                [iconLabel.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
                [iconLabel.centerYAnchor constraintEqualToAnchor:button.centerYAnchor],
                [iconLabel.leadingAnchor constraintGreaterThanOrEqualToAnchor:button.leadingAnchor constant:4.0],
                [iconLabel.trailingAnchor constraintLessThanOrEqualToAnchor:button.trailingAnchor constant:-4.0],
            ]];
        }
        button.accessibilityLabel = item.title;
        button.accessibilityValue = item.toggleStateProvider != nil ? (item.toggleStateProvider() ? @"On" : @"Off") : nil;
        [button addTarget:self action:@selector(toolbarButtonPressed:) forControlEvents:UIControlEventPrimaryActionTriggered];
        UIStackView *row = index < kBrowserNavigationToolbarItemCount ? navigationToolbar : quickToolbar;
        [row addArrangedSubview:button];
        [toolbarButtons addObject:button];
    }];
    self.toolbarButtons = toolbarButtons;

    UIView *toolbarSeparator = [UIView new];
    toolbarSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    toolbarSeparator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    [panelView.contentView addSubview:toolbarSeparator];

    UIView *separator = [UIView new];
    separator.translatesAutoresizingMaskIntoConstraints = NO;
    if (@available(tvOS 13.0, *)) {
        separator.backgroundColor = UIColor.separatorColor;
    } else {
        separator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.2];
    }
    [panelView.contentView addSubview:separator];

    UILabel *footerLabel = [UILabel new];
    footerLabel.translatesAutoresizingMaskIntoConstraints = NO;
    footerLabel.text = self.footerText;
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.font = [UIFont systemFontOfSize:20.0 weight:UIFontWeightRegular];
    if (@available(tvOS 13.0, *)) {
        footerLabel.textColor = UIColor.secondaryLabelColor;
    } else {
        footerLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    }
    [panelView.contentView addSubview:footerLabel];

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.translatesAutoresizingMaskIntoConstraints = NO;
    tableView.dataSource = self;
    tableView.delegate = self;
    tableView.rowHeight = 68.0;
    tableView.backgroundColor = UIColor.clearColor;
    tableView.preservesSuperviewLayoutMargins = NO;
    tableView.layoutMargins = UIEdgeInsetsZero;
    if (@available(tvOS 11.0, *)) {
        tableView.directionalLayoutMargins = NSDirectionalEdgeInsetsZero;
        tableView.insetsLayoutMarginsFromSafeArea = NO;
    }
    tableView.cellLayoutMarginsFollowReadableWidth = NO;
    tableView.clipsToBounds = NO;
    tableView.layer.cornerRadius = 0.0;
    tableView.remembersLastFocusedIndexPath = YES;
    tableView.contentInset = UIEdgeInsetsZero;
    tableView.showsVerticalScrollIndicator = NO;
    if (@available(tvOS 11.0, *)) {
        tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
        tableView.insetsContentViewsToSafeArea = NO;
    }
    [panelView.contentView addSubview:tableView];
    self.tableView = tableView;

    self.panelTrailingConstraint = [panelView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor
                                                                             constant:self.panelWidth + 32.0];

    NSMutableArray<NSLayoutConstraint *> *constraints = [NSMutableArray arrayWithArray:@[
        [dimView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [dimView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [dimView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [dimView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [panelView.widthAnchor constraintEqualToConstant:self.panelWidth],
        [panelView.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:16.0],
        [panelView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-16.0],
        self.panelTrailingConstraint,

        [addressButton.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:24.0],
        [addressButton.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-24.0],
        [addressButton.topAnchor constraintEqualToAnchor:panelView.topAnchor constant:24.0],
        [addressButton.heightAnchor constraintEqualToConstant:64.0],
        [addressIcon.leadingAnchor constraintEqualToAnchor:addressButton.leadingAnchor constant:18.0],
        [addressIcon.centerYAnchor constraintEqualToAnchor:addressButton.centerYAnchor],
        [addressIcon.widthAnchor constraintEqualToConstant:32.0],
        [addressIcon.heightAnchor constraintEqualToConstant:32.0],
        [addressLabel.leadingAnchor constraintEqualToAnchor:addressIcon.trailingAnchor constant:14.0],
        [addressLabel.trailingAnchor constraintEqualToAnchor:addressButton.trailingAnchor constant:-18.0],
        [addressLabel.centerYAnchor constraintEqualToAnchor:addressButton.centerYAnchor],

        [navigationToolbar.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:24.0],
        [navigationToolbar.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-24.0],
        [navigationToolbar.topAnchor constraintEqualToAnchor:addressButton.bottomAnchor constant:18.0],
        [navigationToolbar.heightAnchor constraintEqualToConstant:64.0],

        [toolbarSeparator.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:32.0],
        [toolbarSeparator.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-32.0],
        [toolbarSeparator.topAnchor constraintEqualToAnchor:navigationToolbar.bottomAnchor constant:14.0],
        [toolbarSeparator.heightAnchor constraintEqualToConstant:1.0],

        [quickToolbar.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:24.0],
        [quickToolbar.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-24.0],
        [quickToolbar.topAnchor constraintEqualToAnchor:toolbarSeparator.bottomAnchor constant:14.0],
        [quickToolbar.heightAnchor constraintEqualToConstant:64.0],

        [separator.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:20.0],
        [separator.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-20.0],
        [separator.topAnchor constraintEqualToAnchor:quickToolbar.bottomAnchor constant:16.0],
        [separator.heightAnchor constraintEqualToConstant:1.0],

        [tableView.topAnchor constraintEqualToAnchor:separator.bottomAnchor constant:12.0],
        [tableView.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:16.0],
        [tableView.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-16.0],
        [tableView.bottomAnchor constraintEqualToAnchor:footerLabel.topAnchor constant:-8.0],

        [footerLabel.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:24.0],
        [footerLabel.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-24.0],
        [footerLabel.bottomAnchor constraintEqualToAnchor:panelView.bottomAnchor constant:-12.0],
    ]];
    if (panelTint != nil) {
        [constraints addObject:[panelTint.leadingAnchor constraintEqualToAnchor:panelView.contentView.leadingAnchor]];
        [constraints addObject:[panelTint.trailingAnchor constraintEqualToAnchor:panelView.contentView.trailingAnchor]];
        [constraints addObject:[panelTint.topAnchor constraintEqualToAnchor:panelView.contentView.topAnchor]];
        [constraints addObject:[panelTint.bottomAnchor constraintEqualToAnchor:panelView.contentView.bottomAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (self.didAnimateIn) {
        return;
    }
    self.didAnimateIn = YES;
    self.panelTrailingConstraint.constant = -16.0;
    [UIView animateWithDuration:0.28
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.dimView.alpha = 1.0;
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    if (!self.isBeingDismissed || self.dismissalInProgress) {
        return;
    }

    self.panelTrailingConstraint.constant = self.panelWidth + 32.0;
    id<UIViewControllerTransitionCoordinator> coordinator = self.transitionCoordinator;
    if (coordinator != nil) {
        [coordinator animateAlongsideTransition:^(__unused id<UIViewControllerTransitionCoordinatorContext> context) {
            self.dimView.alpha = 0.0;
            [self.view layoutIfNeeded];
        } completion:nil];
        return;
    }

    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.dimView.alpha = 0.0;
        [self.view layoutIfNeeded];
    } completion:nil];
}

- (void)dismissMenuWithCompletion:(void (^)(void))completion {
    if (self.dismissalInProgress) {
        return;
    }
    self.dismissalInProgress = YES;
    self.panelTrailingConstraint.constant = self.panelWidth + 32.0;
    [UIView animateWithDuration:0.22
                          delay:0.0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
        self.dimView.alpha = 0.0;
        [self.view layoutIfNeeded];
    } completion:^(__unused BOOL finished) {
        [self dismissViewControllerAnimated:NO completion:completion];
    }];
}

- (NSInteger)numberOfSectionsInTableView:(__unused UITableView *)tableView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)tableView:(__unused UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sections.count) {
        return 0;
    }
    return (NSInteger)self.sections[(NSUInteger)section].items.count;
}

- (NSString *)tableView:(__unused UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section < 0 || section >= (NSInteger)self.sections.count) {
        return nil;
    }
    return self.sections[(NSUInteger)section].title;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const kCellIdentifier = @"BrowserAdvancedMenuCell";
    static NSInteger const kMenuTitleLabelTag = 9191;
    static NSInteger const kMenuFocusBackgroundTag = 9292;
    static NSInteger const kMenuToggleTrackTag = 9393;
    static NSInteger const kMenuToggleThumbTag = 9494;
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kCellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kCellIdentifier];
        cell.backgroundColor = UIColor.clearColor;
        cell.contentView.backgroundColor = UIColor.clearColor;
        cell.clipsToBounds = NO;
        cell.contentView.clipsToBounds = NO;
        cell.preservesSuperviewLayoutMargins = NO;
        cell.layoutMargins = UIEdgeInsetsZero;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        if ([cell respondsToSelector:@selector(setFocusStyle:)]) {
            [cell setValue:@(1) forKey:@"focusStyle"]; // UITableViewCellFocusStyleCustom
        }

        UIView *focusBackgroundView = [UIView new];
        focusBackgroundView.translatesAutoresizingMaskIntoConstraints = NO;
        focusBackgroundView.tag = kMenuFocusBackgroundTag;
        focusBackgroundView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
        focusBackgroundView.layer.cornerRadius = 12.0;
        focusBackgroundView.alpha = 0.0;
        [cell.contentView addSubview:focusBackgroundView];

        UILabel *titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.tag = kMenuTitleLabelTag;
        titleLabel.font = [UIFont systemFontOfSize:31.0 weight:UIFontWeightRegular];
        titleLabel.textAlignment = NSTextAlignmentLeft;
        titleLabel.numberOfLines = 1;
        [cell.contentView addSubview:titleLabel];

        UIView *toggleTrack = [UIView new];
        toggleTrack.translatesAutoresizingMaskIntoConstraints = NO;
        toggleTrack.tag = kMenuToggleTrackTag;
        toggleTrack.layer.cornerRadius = 18.0;
        [cell.contentView addSubview:toggleTrack];

        UIView *toggleThumb = [UIView new];
        toggleThumb.translatesAutoresizingMaskIntoConstraints = NO;
        toggleThumb.tag = kMenuToggleThumbTag;
        toggleThumb.backgroundColor = UIColor.whiteColor;
        toggleThumb.layer.cornerRadius = 14.0;
        [toggleTrack addSubview:toggleThumb];

        [NSLayoutConstraint activateConstraints:@[
            [focusBackgroundView.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:0.0],
            [focusBackgroundView.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:0.0],
            [focusBackgroundView.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:2.0],
            [focusBackgroundView.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-2.0],

            [titleLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:24.0],
            [titleLabel.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-24.0],
            [titleLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],

            [toggleTrack.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-24.0],
            [toggleTrack.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [toggleTrack.widthAnchor constraintEqualToConstant:66.0],
            [toggleTrack.heightAnchor constraintEqualToConstant:36.0],
            [toggleThumb.leadingAnchor constraintEqualToAnchor:toggleTrack.leadingAnchor constant:4.0],
            [toggleThumb.centerYAnchor constraintEqualToAnchor:toggleTrack.centerYAnchor],
            [toggleThumb.widthAnchor constraintEqualToConstant:28.0],
            [toggleThumb.heightAnchor constraintEqualToConstant:28.0],
        ]];
    }

    BrowserAdvancedMenuSection *section = self.sections[(NSUInteger)indexPath.section];
    BrowserAdvancedMenuItem *item = section.items[(NSUInteger)indexPath.row];
    UILabel *titleLabel = (UILabel *)[cell.contentView viewWithTag:kMenuTitleLabelTag];
    UIView *focusBackgroundView = [cell.contentView viewWithTag:kMenuFocusBackgroundTag];
    UIView *toggleTrack = [cell.contentView viewWithTag:kMenuToggleTrackTag];
    UIView *toggleThumb = [toggleTrack viewWithTag:kMenuToggleThumbTag];
    titleLabel.text = item.title;
    UIColor *titleColor = nil;
    if (item.style == UIAlertActionStyleDestructive) {
        titleColor = UIColor.redColor;
    } else if (@available(tvOS 13.0, *)) {
        titleColor = UIColor.labelColor;
    } else {
        titleColor = UIColor.whiteColor;
    }
    titleLabel.textColor = titleColor;
    BOOL isToggle = item.toggleStateProvider != nil;
    BOOL isOn = isToggle && item.toggleStateProvider();
    toggleTrack.hidden = !isToggle;
    toggleTrack.backgroundColor = isOn ? [UIColor colorWithRed:0.20 green:0.74 blue:0.39 alpha:1.0]
                                      : [UIColor colorWithWhite:0.45 alpha:0.75];
    toggleThumb.transform = CGAffineTransformMakeTranslation(isOn ? 30.0 : 0.0, 0.0);
    cell.accessibilityValue = isToggle ? (isOn ? @"On" : @"Off") : nil;
    focusBackgroundView.alpha = cell.isFocused ? 1.0 : 0.0;
    return cell;
}

- (void)tableView:(UITableView *)tableView
didUpdateFocusInContext:(UITableViewFocusUpdateContext *)context
withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    NSIndexPath *previousIndexPath = context.previouslyFocusedIndexPath;
    NSIndexPath *nextIndexPath = context.nextFocusedIndexPath;

    UITableViewCell *previousCell = previousIndexPath ? [tableView cellForRowAtIndexPath:previousIndexPath] : nil;
    UITableViewCell *nextCell = nextIndexPath ? [tableView cellForRowAtIndexPath:nextIndexPath] : nil;

    [coordinator addCoordinatedAnimations:^{
        UIView *previousFocusBackground = [previousCell.contentView viewWithTag:9292];
        previousFocusBackground.alpha = 0.0;

        UIView *nextFocusBackground = [nextCell.contentView viewWithTag:9292];
        nextFocusBackground.alpha = 1.0;
    } completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    BrowserAdvancedMenuSection *section = self.sections[(NSUInteger)indexPath.section];
    BrowserAdvancedMenuItem *item = section.items[(NSUInteger)indexPath.row];
    BrowserAdvancedMenuItemHandler handler = item.handler;
    if (item.toggleStateProvider != nil) {
        if (handler != nil) {
            handler();
        }
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UIView *toggleTrack = [cell.contentView viewWithTag:9393];
        UIView *toggleThumb = [toggleTrack viewWithTag:9494];
        BOOL isOn = item.toggleStateProvider();
        [UIView animateWithDuration:0.18 animations:^{
            toggleTrack.backgroundColor = isOn ? [UIColor colorWithRed:0.20 green:0.74 blue:0.39 alpha:1.0]
                                               : [UIColor colorWithWhite:0.45 alpha:0.75];
            toggleThumb.transform = CGAffineTransformMakeTranslation(isOn ? 30.0 : 0.0, 0.0);
        }];
        cell.accessibilityValue = isOn ? @"On" : @"Off";
        return;
    }
    [self dismissMenuWithCompletion:^{
        if (handler != nil) {
            handler();
        }
    }];
}

- (void)toolbarButtonPressed:(UIButton *)button {
    NSInteger index = button.tag - 10000;
    if (index < 0 || index >= (NSInteger)self.toolbarItems.count) {
        return;
    }
    BrowserAdvancedMenuItem *item = self.toolbarItems[(NSUInteger)index];
    if (!item.enabled || item.handler == nil) {
        return;
    }
    if (item.keepsMenuOpen) {
        item.handler();
        if (item.toggleStateProvider != nil) {
            BOOL isOn = item.toggleStateProvider();
            button.backgroundColor = isOn ? [UIColor colorWithRed:0.20 green:0.54 blue:0.90 alpha:0.72]
                                          : [UIColor colorWithWhite:1.0 alpha:0.12];
            button.accessibilityValue = isOn ? @"On" : @"Off";
        }
    } else {
        [self dismissMenuWithCompletion:item.handler];
    }
}

- (void)addressButtonPressed:(__unused UIButton *)button {
    if (self.addressHandler != nil) {
        [self dismissMenuWithCompletion:self.addressHandler];
    }
}

- (NSArray<id<UIFocusEnvironment>> *)preferredFocusEnvironments {
    if (self.addressButton.enabled) {
        return @[self.addressButton];
    }
    for (UIButton *button in self.toolbarButtons) {
        if (button.enabled) {
            return @[button];
        }
    }
    return @[self.tableView];
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    UIView *previousView = context.previouslyFocusedView;
    UIView *nextView = context.nextFocusedView;
    if (previousView == self.addressButton) {
        ((UILabel *)[self.addressButton viewWithTag:9898]).textColor = UIColor.whiteColor;
        [self setToolbarIconColor:UIColor.whiteColor forButton:self.addressButton];
    }
    if (nextView == self.addressButton) {
        ((UILabel *)[self.addressButton viewWithTag:9898]).textColor = UIColor.blackColor;
        [self setToolbarIconColor:UIColor.blackColor forButton:self.addressButton];
    }
    if ([self.toolbarButtons containsObject:(UIButton *)previousView]) {
        previousView.layer.zPosition = 0.0;
    }
    if ([self.toolbarButtons containsObject:(UIButton *)nextView]) {
        [nextView.superview bringSubviewToFront:nextView];
        nextView.layer.zPosition = 1.0;
    }
    [coordinator addCoordinatedAnimations:^{
        if ([self.toolbarButtons containsObject:(UIButton *)previousView]) {
            [self setToolbarIconColor:UIColor.whiteColor forButton:(UIButton *)previousView];
        }
        if ([self.toolbarButtons containsObject:(UIButton *)nextView]) {
            [self setToolbarIconColor:UIColor.blackColor forButton:(UIButton *)nextView];
        }
    } completion:nil];
}

- (void)setToolbarIconColor:(UIColor *)color forButton:(UIButton *)button {
    UIView *icon = [button viewWithTag:9797];
    if ([icon isKindOfClass:[UIImageView class]]) {
        ((UIImageView *)icon).tintColor = color;
    } else if ([icon isKindOfClass:[UILabel class]]) {
        ((UILabel *)icon).textColor = color;
    }
}

- (void)pressesEnded:(NSSet<UIPress *> *)presses withEvent:(UIPressesEvent *)event {
    UIPress *press = presses.anyObject;
    if (press != nil && press.type == UIPressTypeMenu) {
        [self dismissMenuWithCompletion:nil];
        return;
    }
    [super pressesEnded:presses withEvent:event];
}

@end

@interface BrowserMenuCoordinator ()

@property (nonatomic, weak) id<BrowserMenuCoordinatorHost> host;
@property (nonatomic) BrowserPreferencesStore *preferencesStore;

@end

@implementation BrowserMenuCoordinator

- (instancetype)initWithHost:(id<BrowserMenuCoordinatorHost>)host
            preferencesStore:(BrowserPreferencesStore *)preferencesStore {
    self = [super init];
    if (self) {
        _host = host;
        _preferencesStore = preferencesStore ?: [BrowserPreferencesStore new];
        [_preferencesStore ensureUserAgentConsistency];
    }
    return self;
}

- (void)showAdvancedMenu {
    BrowserAdvancedMenuViewController *menuViewController = [[BrowserAdvancedMenuViewController alloc] initWithToolbarItems:[self advancedMenuToolbarItems]
                                                                                                                     sections:[self advancedMenuSections]
                                                                                                                   footerText:[self advancedMenuFooterText]];
    NSString *address = self.host.browserWebView.request.URL.absoluteString;
    menuViewController.addressText = [address isEqualToString:@"about:blank"] ? @"" : address;
    __weak typeof(self) weakSelf = self;
    menuViewController.addressHandler = ^{
        [weakSelf.host browserEditCurrentAddress];
    };
    [self.host browserPresentViewController:menuViewController];
}

- (UIAlertController *)browserAlertControllerWithTitle:(NSString *)title message:(NSString *)message {
    return [UIAlertController alertControllerWithTitle:title
                                               message:message
                                        preferredStyle:UIAlertControllerStyleAlert];
}

- (UIAlertAction *)browserActionWithTitle:(NSString *)title
                                    style:(UIAlertActionStyle)style
                                  handler:(void (^ __nullable)(UIAlertAction *action))handler {
    return [UIAlertAction actionWithTitle:title style:style handler:handler];
}

- (BrowserAdvancedMenuItem *)advancedMenuItemWithTitle:(NSString *)title
                                                  style:(UIAlertActionStyle)style
                                                handler:(BrowserAdvancedMenuItemHandler)handler {
    return [BrowserAdvancedMenuItem itemWithTitle:title style:style handler:handler];
}

- (UIAlertAction *)browserCancelAction {
    return [self browserActionWithTitle:nil style:UIAlertActionStyleCancel handler:nil];
}

- (BOOL)stringHasVisibleContent:(NSString *)string {
    NSString *trimmedString = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return trimmedString.length > 0;
}

- (NSString *)displayTitleForStoredTitle:(NSString *)storedTitle
                               URLString:(NSString *)URLString
                              includeURL:(BOOL)includeURL {
    NSString *displayTitle = [self stringHasVisibleContent:storedTitle] ? storedTitle : URLString;
    if (includeURL && [self stringHasVisibleContent:storedTitle] && [self stringHasVisibleContent:URLString]) {
        return [NSString stringWithFormat:@"%@ - %@", storedTitle, URLString];
    }
    return displayTitle ?: @"";
}

- (void)loadStoredURLString:(NSString *)URLString {
    if (![self stringHasVisibleContent:URLString]) {
        return;
    }
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    NSString *userAgent = self.preferencesStore.userAgent;
    if (userAgent.length > 0) {
        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    [[self.host browserWebView] loadRequest:request];
}

- (void)saveFavoritesArray:(NSArray *)favorites {
    [[NSUserDefaults standardUserDefaults] setObject:favorites forKey:@"FAVORITES"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)presentDeleteFavoriteMenu {
    NSArray *favorites = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Delete a Favorite"
                                                                       message:@"Select a Favorite to Delete"];
    __weak typeof(self) weakSelf = self;
    
    [favorites enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        if (![weakSelf stringHasVisibleContent:URLString]) {
            return;
        }
        
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:NO];
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            NSMutableArray *updatedFavorites = [favorites mutableCopy];
            [updatedFavorites removeObjectAtIndex:index];
            [weakSelf saveFavoritesArray:updatedFavorites];
        }]];
    }];
    
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentAddFavoritePrompt {
    NSString *pageTitle = [[self.host browserWebView] title];
    NSURLRequest *request = [[self.host browserWebView] request];
    NSString *currentURL = request.URL.absoluteString ?: @"";
    if (![self stringHasVisibleContent:currentURL]) {
        return;
    }
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Name New Favorite"
                                                                       message:currentURL];
    __weak typeof(self) weakSelf = self;
    
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.keyboardType = UIKeyboardTypeDefault;
        textField.placeholder = @"Name New Favorite";
        textField.text = pageTitle;
        textField.textColor = MenuTextColor();
        [textField setReturnKeyType:UIReturnKeyDone];
    }];
    
    [alertController addAction:[self browserActionWithTitle:@"Save"
                                                      style:UIAlertActionStyleDestructive
                                                    handler:^(__unused UIAlertAction *action) {
        UITextField *titleTextField = alertController.textFields.firstObject;
        NSString *savedTitle = titleTextField.text;
        if (![weakSelf stringHasVisibleContent:savedTitle]) {
            savedTitle = currentURL;
        }
        
        NSArray *favoriteEntry = @[currentURL, savedTitle ?: @""];
        NSMutableArray *favorites = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"] mutableCopy];
        if (favorites == nil) {
            favorites = [NSMutableArray array];
        }
        NSUInteger existingIndex = [favorites indexOfObjectPassingTest:^BOOL(id entry, NSUInteger index, BOOL *stop) {
            return [entry isKindOfClass:[NSArray class]] && [entry count] > 0 && [entry[0] isEqualToString:currentURL];
        }];
        if (existingIndex != NSNotFound) {
            [favorites replaceObjectAtIndex:existingIndex withObject:favoriteEntry];
        } else {
            [favorites addObject:favoriteEntry];
        }
        [weakSelf saveFavoritesArray:favorites];
    }]];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentFavoritesMenu {
    NSArray *favorites = [[NSUserDefaults standardUserDefaults] arrayForKey:@"FAVORITES"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Favorites" message:@""];
    __weak typeof(self) weakSelf = self;
    
    [favorites enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:NO];
        if (![weakSelf stringHasVisibleContent:displayTitle]) {
            return;
        }
        
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            [weakSelf loadStoredURLString:URLString];
        }]];
    }];
    
    if (favorites.count > 0) {
        [alertController addAction:[self browserActionWithTitle:@"Delete a Favorite"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(__unused UIAlertAction *action) {
            [weakSelf presentDeleteFavoriteMenu];
        }]];
    }
    
    [alertController addAction:[self browserActionWithTitle:@"Add Current Page to Favorites"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(__unused UIAlertAction *action) {
        [weakSelf presentAddFavoritePrompt];
    }]];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentHistoryMenu {
    NSArray *historyEntries = [[NSUserDefaults standardUserDefaults] arrayForKey:@"HISTORY"];
    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"History" message:@""];
    __weak typeof(self) weakSelf = self;
    
    if (historyEntries.count > 0) {
        [alertController addAction:[self browserActionWithTitle:@"Clear History"
                                                          style:UIAlertActionStyleDestructive
                                                        handler:^(__unused UIAlertAction *action) {
            [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"HISTORY"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }]];
    }
    
    [historyEntries enumerateObjectsUsingBlock:^(NSArray *entry, NSUInteger index, BOOL *stop) {
        NSString *URLString = entry.count > 0 ? entry[0] : @"";
        NSString *title = entry.count > 1 ? entry[1] : @"";
        NSString *displayTitle = [weakSelf displayTitleForStoredTitle:title URLString:URLString includeURL:YES];
        if (![weakSelf stringHasVisibleContent:displayTitle]) {
            return;
        }
        
        [alertController addAction:[weakSelf browserActionWithTitle:displayTitle
                                                              style:UIAlertActionStyleDefault
                                                            handler:^(__unused UIAlertAction *action) {
            [weakSelf loadStoredURLString:URLString];
        }]];
    }];
    
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)applyUserAgent:(NSString *)userAgent mobileMode:(BOOL)mobileMode {
    self.preferencesStore.userAgent = userAgent;
    self.preferencesStore.mobileModeEnabled = mobileMode;
    
    NSURLRequest *request = [[self.host browserWebView] request];
    if (request != nil && [self stringHasVisibleContent:request.URL.absoluteString]) {
        [self.host browserCaptureSnapshotForCurrentTab];
    }
    
    [self.host browserRecreateActiveWebViewPreservingCurrentURL];
    [self.host browserBringCursorToFront];
}

- (void)setPageScalingEnabled:(BOOL)enabled {
    self.preferencesStore.scalePagesToFit = enabled;
    if (enabled) {
        self.preferencesStore.pageZoomPercent = 100;
        self.host.browserWebView.pageZoomFactor = 1.0;
    }
    [[self.host browserWebView] setScalesPageToFit:enabled];
    if (enabled) {
        [[self.host browserWebView] setContentMode:UIViewContentModeScaleAspectFit];
    }
    [[self.host browserWebView] reload];
}

- (void)setPageZoomPercent:(NSUInteger)percent {
    BrowserWebView *webView = self.host.browserWebView;
    UIScrollView *scrollView = webView.scrollView;
    CGFloat previousZoom = self.preferencesStore.pageZoomPercent / 100.0;
    CGFloat visibleWidth = CGRectGetWidth(scrollView.bounds);
    CGFloat centerX = scrollView.contentOffset.x + visibleWidth / 2.0;

    self.preferencesStore.pageZoomPercent = percent;
    self.preferencesStore.scalePagesToFit = NO;
    webView.scalesPageToFit = NO;
    webView.contentMode = UIViewContentModeScaleToFill;
    webView.pageZoomFactor = self.preferencesStore.pageZoomPercent / 100.0;
    self.host.browserTextFontSize = self.preferencesStore.pageZoomPercent;
    [self.host browserUpdateTextFontSize];

    // WebKit updates its scrollable width after applying page and text zoom.
    // Keep the point previously at the screen center in the same place.
    CGFloat targetCenterX = centerX * (percent / 100.0) / MAX(previousZoom, 0.01);
    __weak typeof(self) weakSelf = self;
    __weak BrowserWebView *weakWebView = webView;
    for (NSNumber *delay in @[@0.0, @0.2, @0.7]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            BrowserWebView *currentWebView = weakWebView;
            if (currentWebView == nil || weakSelf.host.browserWebView != currentWebView ||
                weakSelf.preferencesStore.pageZoomPercent != percent) {
                return;
            }
            UIScrollView *currentScrollView = currentWebView.scrollView;
            CGFloat width = CGRectGetWidth(currentScrollView.bounds);
            CGFloat maximumX = MAX(0.0, currentScrollView.contentSize.width - width);
            CGFloat targetX = MIN(MAX(targetCenterX - width / 2.0, 0.0), maximumX);
            [currentScrollView setContentOffset:CGPointMake(targetX, currentScrollView.contentOffset.y) animated:NO];
        });
    }
}

- (void)clearCacheAndReload {
    __weak typeof(self) weakSelf = self;
    [BrowserWebView clearCachedDataWithCompletion:^{
        weakSelf.host.browserPreviousURL = @"";
        [[weakSelf.host browserWebView] reload];
    }];
}

- (void)clearCookiesAndReload {
    __weak typeof(self) weakSelf = self;
    [BrowserWebView clearCookiesWithCompletion:^{
        weakSelf.host.browserPreviousURL = @"";
        [[weakSelf.host browserWebView] reload];
    }];
}

- (NSString *)mediaDiagnosticsJavaScript {
    return @"(function(){"
            "function canPlay(type){"
                "try {"
                    "var video=document.createElement('video');"
                    "if (!video || typeof video.canPlayType!=='function') { return 'n/a'; }"
                    "var value=video.canPlayType(type);"
                    "return value ? String(value) : '';"
                "} catch (error) { return 'error'; }"
            "}"
            "function mse(type){"
                "try {"
                    "if (typeof MediaSource==='undefined' || typeof MediaSource.isTypeSupported!=='function') { return 'n/a'; }"
                    "return MediaSource.isTypeSupported(type) ? 'yes' : 'no';"
                "} catch (error) { return 'error'; }"
            "}"
            "function probeGlobal(name){"
                "try {"
                    "var value=window[name];"
                    "if (typeof value==='undefined') { return 'undefined'; }"
                    "if (value === null) { return 'null'; }"
                    "return typeof value;"
                "} catch (error) { return 'error'; }"
            "}"
            "var video=document.querySelector('video');"
            "var result={"
                "href:(window.location && window.location.href) ? String(window.location.href) : '',"
                "title:(document && document.title) ? String(document.title) : '',"
                "userAgent:(navigator && navigator.userAgent) ? String(navigator.userAgent) : '',"
                "platform:(navigator && navigator.platform) ? String(navigator.platform) : '',"
                "mediaSource:(typeof MediaSource!=='undefined') ? 'yes' : 'no',"
                "managedMediaSource:(typeof ManagedMediaSource!=='undefined') ? 'yes' : 'no',"
                "mediaCapabilities:(typeof navigator.mediaCapabilities!=='undefined') ? 'yes' : 'no',"
                "videoElement:video ? 'yes' : 'no',"
                "videoSrc:video ? String(video.currentSrc||video.src||'') : '',"
                "globalMediaSource:probeGlobal('MediaSource'),"
                "globalManagedMediaSource:probeGlobal('ManagedMediaSource'),"
                "globalWebKitMediaSource:probeGlobal('WebKitMediaSource'),"
                "globalSourceBuffer:probeGlobal('SourceBuffer'),"
                "globalManagedSourceBuffer:probeGlobal('ManagedSourceBuffer'),"
                "globalWebKitSourceBuffer:probeGlobal('WebKitSourceBuffer'),"
                "hls:canPlay('application/vnd.apple.mpegurl'),"
                "mp4H264:canPlay('video/mp4; codecs=\"avc1.42E01E, mp4a.40.2\"'),"
                "mp4Hevc:canPlay('video/mp4; codecs=\"hvc1.1.6.L93.B0, mp4a.40.2\"'),"
                "webmVp9:canPlay('video/webm; codecs=\"vp9\"'),"
                "mp4Av1:canPlay('video/mp4; codecs=\"av01.0.05M.08, mp4a.40.2\"'),"
                "webmAv1:canPlay('video/webm; codecs=\"av01.0.05M.08\"'),"
                "mseMp4H264:mse('video/mp4; codecs=\"avc1.42E01E, mp4a.40.2\"'),"
                "mseWebmVp9:mse('video/webm; codecs=\"vp9\"'),"
                "mseMp4Av1:mse('video/mp4; codecs=\"av01.0.05M.08, mp4a.40.2\"'),"
                "mseWebmAv1:mse('video/webm; codecs=\"av01.0.05M.08\"')"
            "};"
            "return JSON.stringify(result);"
           "})()";
}

- (NSDictionary *)mediaDiagnosticsDictionary {
    NSString *resultString = [[self.host browserWebView] stringByEvaluatingJavaScriptFromString:[self mediaDiagnosticsJavaScript]];
    if (![self stringHasVisibleContent:resultString]) {
        return nil;
    }

    NSData *resultData = [resultString dataUsingEncoding:NSUTF8StringEncoding];
    if (resultData == nil) {
        return nil;
    }

    id object = [NSJSONSerialization JSONObjectWithData:resultData options:0 error:nil];
    if (![object isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return object;
}

- (NSString *)stringValueForDiagnosticsKey:(NSString *)key dictionary:(NSDictionary *)dictionary fallback:(NSString *)fallback {
    id value = dictionary[key];
    if ([value isKindOfClass:[NSString class]] && [self stringHasVisibleContent:value]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        NSString *stringValue = [value stringValue];
        if ([self stringHasVisibleContent:stringValue]) {
            return stringValue;
        }
    }
    return fallback;
}

- (void)presentMediaDiagnostics {
    NSDictionary *diagnostics = [self mediaDiagnosticsDictionary];
    if (diagnostics == nil) {
        UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Media Diagnostics"
                                                                           message:@"The page did not return diagnostics data."];
        [alertController addAction:[self browserCancelAction]];
        [self.host browserPresentViewController:alertController];
        return;
    }

    BOOL mobileModeEnabled = self.preferencesStore.mobileModeEnabled;
    NSString *message = [NSString stringWithFormat:
                         @"Mode: %@\n"
                          "URL: %@\n"
                          "UA: %@\n\n"
                          "MediaSource: %@\n"
                          "ManagedMediaSource: %@\n"
                          "MediaCapabilities: %@\n"
                          "Video Element: %@\n"
                          "Video Src: %@\n\n"
                          "Global MediaSource: %@\n"
                          "Global ManagedMediaSource: %@\n"
                          "Global WebKitMediaSource: %@\n"
                          "Global SourceBuffer: %@\n"
                          "Global ManagedSourceBuffer: %@\n"
                          "Global WebKitSourceBuffer: %@\n\n"
                          "canPlay HLS: %@\n"
                          "canPlay MP4 H.264: %@\n"
                          "canPlay MP4 HEVC: %@\n"
                          "canPlay WebM VP9: %@\n"
                          "canPlay MP4 AV1: %@\n"
                          "canPlay WebM AV1: %@\n\n"
                          "MSE MP4 H.264: %@\n"
                          "MSE WebM VP9: %@\n"
                          "MSE MP4 AV1: %@\n"
                          "MSE WebM AV1: %@",
                         mobileModeEnabled ? @"Mobile" : @"Desktop",
                         [self stringValueForDiagnosticsKey:@"href" dictionary:diagnostics fallback:@"Unavailable"],
                         [self stringValueForDiagnosticsKey:@"userAgent" dictionary:diagnostics fallback:@"Unavailable"],
                         [self stringValueForDiagnosticsKey:@"mediaSource" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"managedMediaSource" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mediaCapabilities" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"videoElement" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"videoSrc" dictionary:diagnostics fallback:@"Unavailable"],
                         [self stringValueForDiagnosticsKey:@"globalMediaSource" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"globalManagedMediaSource" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"globalWebKitMediaSource" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"globalSourceBuffer" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"globalManagedSourceBuffer" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"globalWebKitSourceBuffer" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"hls" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mp4H264" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mp4Hevc" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"webmVp9" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mp4Av1" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"webmAv1" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mseMp4H264" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mseWebmVp9" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mseMp4Av1" dictionary:diagnostics fallback:@"n/a"],
                         [self stringValueForDiagnosticsKey:@"mseWebmAv1" dictionary:diagnostics fallback:@"n/a"]];

    NSLog(@"%@ %@", kBrowserMediaDiagnosticsLogPrefix, message);

    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"Media Diagnostics"
                                                                       message:message];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (void)presentWebKitRuntimeMediaPreferences {
    NSString *report = [[self.host browserWebView] runtimeMediaPreferenceReport];
    if (![self stringHasVisibleContent:report]) {
        report = @"No runtime WebKit media preference information was returned.";
    }

    NSLog(@"%@ %@", kBrowserWebKitMediaPrefsLogPrefix, report);

    NSString *message = report;
    if (message.length > 1800) {
        message = [[message substringToIndex:1800] stringByAppendingString:@"\n\nFull report logged to console."];
    }

    UIAlertController *alertController = [self browserAlertControllerWithTitle:@"WebKit Media Prefs"
                                                                       message:message];
    [alertController addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:alertController];
}

- (BrowserAdvancedMenuItem *)usageGuideMenuItem {
    return [self advancedMenuItemWithTitle:@"Usage Guide"
                                     style:UIAlertActionStyleDefault
                                   handler:^{
        [self.host browserShowHints];
    }];
}

- (UIAlertAction *)wkWebViewProofOfConceptAction {
    return [self browserActionWithTitle:@"Open WKWebView PoC"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        Class proofOfConceptControllerClass = NSClassFromString(@"BrowserWKWebViewProofOfConceptViewController");
        UIViewController *viewController = nil;
        if (proofOfConceptControllerClass != Nil) {
            viewController = [proofOfConceptControllerClass new];
            viewController.modalPresentationStyle = UIModalPresentationFullScreen;
        } else {
            viewController = [UIAlertController alertControllerWithTitle:@"WKWebView PoC Missing"
                                                                 message:@"The proof-of-concept controller was not compiled into this build."
                                                          preferredStyle:UIAlertControllerStyleAlert];
            [(UIAlertController *)viewController addAction:[self browserCancelAction]];
        }
        [self.host browserPresentViewController:viewController];
    }];
}

- (BrowserAdvancedMenuItem *)favoritesMenuItem {
    return [self advancedMenuItemWithTitle:@"Favorites"
                                     style:UIAlertActionStyleDefault
                                   handler:^{
        [self presentFavoritesMenu];
    }];
}

- (BrowserAdvancedMenuItem *)userAgentModeMenuItem {
    BrowserAdvancedMenuItem *item = [self advancedMenuItemWithTitle:@"Mobile User Agent"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^{
        BOOL mobileMode = !self.preferencesStore.mobileModeEnabled;
        NSString *userAgent = mobileMode ? BrowserPreferencesStore.mobileUserAgent : BrowserPreferencesStore.desktopUserAgent;
        [self applyUserAgent:userAgent mobileMode:mobileMode];
    }];
    item.toggleStateProvider = ^BOOL {
        return self.preferencesStore.mobileModeEnabled;
    };
    return item;
}

- (BrowserAdvancedMenuItem *)pageScalingMenuItem {
    BrowserAdvancedMenuItem *item = [self advancedMenuItemWithTitle:@"Scale Pages to Fit"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^{
        [self setPageScalingEnabled:!self.preferencesStore.scalePagesToFit];
    }];
    item.toggleStateProvider = ^BOOL {
        return self.preferencesStore.scalePagesToFit;
    };
    return item;
}

- (BrowserAdvancedMenuItem *)cursorMagnifierToggleMenuItem {
    BrowserAdvancedMenuItem *item = [self advancedMenuItemWithTitle:@"Cursor Magnifier"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^{
        self.host.browserCursorMagnifierEnabled = !self.host.browserCursorMagnifierEnabled;
    }];
    item.toggleStateProvider = ^BOOL {
        return self.host.browserCursorMagnifierEnabled;
    };
    return item;
}

- (UIAlertAction *)playVideoUnderCursorAction {
    return [self browserActionWithTitle:@"Play Active Video"
                                  style:UIAlertActionStyleDefault
                                handler:^(__unused UIAlertAction *action) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.host browserPlayVideoUnderCursorIfAvailable];
        });
    }];
}

- (BrowserAdvancedMenuItem *)fullscreenVideoPlaybackToggleMenuItem {
    BrowserAdvancedMenuItem *item = [self advancedMenuItemWithTitle:@"Full Screen Player"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^{
        self.host.browserFullscreenVideoPlaybackEnabled = !self.host.browserFullscreenVideoPlaybackEnabled;
    }];
    item.toggleStateProvider = ^BOOL {
        return self.host.browserFullscreenVideoPlaybackEnabled;
    };
    return item;
}

- (BrowserAdvancedMenuItem *)adBlockToggleMenuItem {
    BrowserAdvancedMenuItem *item = [self advancedMenuItemWithTitle:@"Ad Block"
                                                               style:UIAlertActionStyleDefault
                                                             handler:^{
        BOOL enabled = self.preferencesStore.adBlockEnabled;
        BOOL removalUnavailable = [self.host.browserWebView.adBlockStatus isEqualToString:@"removal-unavailable"];
        BOOL newValue = removalUnavailable ? NO : !enabled;
        self.preferencesStore.adBlockEnabled = newValue;
        [self.host browserSetAdBlockEnabled:newValue];
    }];
    item.toggleStateProvider = ^BOOL {
        return self.preferencesStore.adBlockEnabled ||
            [self.host.browserWebView.adBlockStatus isEqualToString:@"removal-unavailable"];
    };
    return item;
}

- (NSArray<BrowserAdvancedMenuItem *> *)advancedMenuToolbarItems {
    BrowserAdvancedMenuItem *backItem = [self advancedMenuItemWithTitle:@"Back"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^{
        BrowserWebView *webView = self.host.browserWebView;
        if (webView.canGoBack) {
            [webView goBack];
        }
    }];
    backItem.enabled = self.host.browserWebView.canGoBack;
    BrowserAdvancedMenuItem *homeItem = [self advancedMenuItemWithTitle:@"Home"
                                                                  style:UIAlertActionStyleDefault
                                                                handler:^{
        [self.host browserLoadHomePage];
    }];
    BrowserAdvancedMenuItem *reloadItem = [self advancedMenuItemWithTitle:@"Reload Page"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^{
        [self.host.browserWebView reload];
    }];
    BrowserAdvancedMenuItem *forwardItem = [self advancedMenuItemWithTitle:@"Forward"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^{
        BrowserWebView *webView = self.host.browserWebView;
        if (webView.canGoForward) {
            [webView goForward];
        }
    }];
    forwardItem.enabled = self.host.browserWebView.canGoForward;
    BrowserAdvancedMenuItem *tabsItem = [self advancedMenuItemWithTitle:@"Tabs"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^{
        [self.host browserShowTabOverview];
    }];
    BrowserAdvancedMenuItem *addFavoriteItem = [self advancedMenuItemWithTitle:@"Add to Favorites"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^{
        [self presentAddFavoritePrompt];
    }];
    BrowserAdvancedMenuItem *historyItem = [self advancedMenuItemWithTitle:@"History"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^{
        [self presentHistoryMenu];
    }];
    BrowserAdvancedMenuItem *zoomOutItem = [self advancedMenuItemWithTitle:@"Zoom Out"
                                                                    style:UIAlertActionStyleDefault
                                                                  handler:^{
        [self setPageZoomPercent:self.preferencesStore.pageZoomPercent - 10];
    }];
    BrowserAdvancedMenuItem *zoomResetItem = [self advancedMenuItemWithTitle:@"Reset Zoom"
                                                                      style:UIAlertActionStyleDefault
                                                                    handler:^{
        [self setPageZoomPercent:100];
    }];
    BrowserAdvancedMenuItem *zoomInItem = [self advancedMenuItemWithTitle:@"Zoom In"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^{
        [self setPageZoomPercent:self.preferencesStore.pageZoomPercent + 10];
    }];
    zoomOutItem.keepsMenuOpen = YES;
    zoomResetItem.keepsMenuOpen = YES;
    zoomInItem.keepsMenuOpen = YES;
    return @[homeItem, backItem, reloadItem, forwardItem, tabsItem,
             addFavoriteItem, historyItem, zoomOutItem, zoomResetItem, zoomInItem];
}

- (NSArray<BrowserAdvancedMenuSection *> *)advancedMenuSections {
    BrowserAdvancedMenuItem *mediaDiagnosticsItem = [self advancedMenuItemWithTitle:@"Media Diagnostics"
                                                                               style:UIAlertActionStyleDefault
                                                                             handler:^{
        [self presentMediaDiagnostics];
    }];
    BrowserAdvancedMenuItem *webkitMediaPrefsItem = [self advancedMenuItemWithTitle:@"Inspect WebKit Media Prefs"
                                                                                style:UIAlertActionStyleDefault
                                                                              handler:^{
        [self presentWebKitRuntimeMediaPreferences];
    }];
    BrowserAdvancedMenuItem *clearCacheItem = [self advancedMenuItemWithTitle:@"Clear Cache"
                                                                         style:UIAlertActionStyleDestructive
                                                                       handler:^{
        [self clearCacheAndReload];
    }];
    BrowserAdvancedMenuItem *clearCookiesItem = [self advancedMenuItemWithTitle:@"Clear Cookies"
                                                                           style:UIAlertActionStyleDestructive
                                                                         handler:^{
        [self clearCookiesAndReload];
    }];

    return @[
        [BrowserAdvancedMenuSection sectionWithTitle:@"Navigation"
                                               items:@[
            [self adBlockToggleMenuItem],
            [self favoritesMenuItem],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Appearance"
                                               items:@[
            [self cursorMagnifierToggleMenuItem],
            [self pageScalingMenuItem],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Video Playback"
                                               items:@[
            [self fullscreenVideoPlaybackToggleMenuItem],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Compatibility"
                                               items:@[
            [self userAgentModeMenuItem],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Diagnostics"
                                               items:@[
            mediaDiagnosticsItem,
            webkitMediaPrefsItem,
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Maintenance"
                                               items:@[
            clearCacheItem,
            clearCookiesItem,
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Help"
                                               items:@[
            [self usageGuideMenuItem],
        ]],
    ];
}

- (NSString *)advancedMenuFooterText {
    NSDictionary *infoDictionary = NSBundle.mainBundle.infoDictionary;
    NSString *version = infoDictionary[@"CFBundleShortVersionString"];
    BOOL hasVersion = [self stringHasVisibleContent:version];

    if (hasVersion) {
        return [NSString stringWithFormat:@"Version %@", version];
    }
    return @"";
}

@end
