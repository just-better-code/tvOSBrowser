#import "BrowserMenuCoordinator.h"
#import "BrowserFavoriteEditorViewController.h"
#import "BrowserHistoryViewController.h"
#import "BrowserHistoryStore.h"
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
static NSUInteger const kBrowserNavigationToolbarItemCount = 4;

typedef void (^BrowserAdvancedMenuItemHandler)(void);
typedef BOOL (^BrowserAdvancedMenuToggleStateProvider)(void);

@interface BrowserAdvancedMenuItem : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *tileTitle;
@property (nonatomic, copy) NSString *tileSymbolName;
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

@interface BrowserAdvancedMenuTileCell : UICollectionViewCell

@property (nonatomic) UIImageView *symbolView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *stateLabel;
@property (nonatomic) BOOL destructive;
@property (nonatomic) BOOL toggle;

- (void)configureWithItem:(BrowserAdvancedMenuItem *)item;

@end

@implementation BrowserAdvancedMenuTileCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = UIColor.clearColor;
        self.contentView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.13];
        self.contentView.layer.cornerRadius = 18.0;
        self.contentView.layer.masksToBounds = YES;

        UIImageView *symbolView = [UIImageView new];
        symbolView.translatesAutoresizingMaskIntoConstraints = NO;
        symbolView.contentMode = UIViewContentModeScaleAspectFit;
        [self.contentView addSubview:symbolView];
        self.symbolView = symbolView;

        UILabel *titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightMedium];
        titleLabel.numberOfLines = 2;
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:titleLabel];
        self.titleLabel = titleLabel;

        UILabel *stateLabel = [UILabel new];
        stateLabel.translatesAutoresizingMaskIntoConstraints = NO;
        stateLabel.font = [UIFont systemFontOfSize:17.0 weight:UIFontWeightSemibold];
        stateLabel.textAlignment = NSTextAlignmentCenter;
        stateLabel.layer.cornerRadius = 14.0;
        stateLabel.layer.masksToBounds = YES;
        [self.contentView addSubview:stateLabel];
        self.stateLabel = stateLabel;

        [NSLayoutConstraint activateConstraints:@[
            [symbolView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [symbolView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18.0],
            [symbolView.widthAnchor constraintEqualToConstant:40.0],
            [symbolView.heightAnchor constraintEqualToConstant:40.0],
            [titleLabel.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:20.0],
            [titleLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [titleLabel.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-17.0],
            [stateLabel.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16.0],
            [stateLabel.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:18.0],
            [stateLabel.widthAnchor constraintEqualToConstant:52.0],
            [stateLabel.heightAnchor constraintEqualToConstant:28.0],
        ]];
    }
    return self;
}

- (void)configureWithItem:(BrowserAdvancedMenuItem *)item {
    self.destructive = item.style == UIAlertActionStyleDestructive;
    self.toggle = item.toggleStateProvider != nil;
    self.titleLabel.text = item.tileTitle.length > 0 ? item.tileTitle : item.title;
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:37.0
                                                                                                 weight:UIImageSymbolWeightMedium];
    UIImage *symbol = [UIImage systemImageNamed:item.tileSymbolName ?: @"square.grid.2x2"
                             withConfiguration:configuration];
    if (symbol == nil) {
        symbol = [UIImage systemImageNamed:@"square.grid.2x2" withConfiguration:configuration];
    }
    self.symbolView.image = [symbol imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    self.stateLabel.hidden = !self.toggle;
    if (self.toggle) {
        BOOL isOn = item.toggleStateProvider();
        self.stateLabel.text = isOn ? @"ON" : @"OFF";
        self.stateLabel.backgroundColor = isOn ? [UIColor colorWithRed:0.20 green:0.72 blue:0.42 alpha:0.95]
                                                   : [UIColor colorWithWhite:0.42 alpha:0.65];
        self.accessibilityValue = isOn ? @"On" : @"Off";
    } else {
        self.accessibilityValue = nil;
    }
    self.accessibilityLabel = item.title;
    [self updateAppearance];
}

- (void)updateAppearance {
    BOOL focused = self.isFocused;
    self.contentView.backgroundColor = focused ? [UIColor colorWithWhite:1.0 alpha:0.96]
                                               : [UIColor colorWithWhite:1.0 alpha:0.13];
    UIColor *foreground = self.destructive ? (focused ? [UIColor colorWithRed:0.65 green:0.10 blue:0.16 alpha:1.0]
                                                    : [UIColor colorWithRed:1.0 green:0.48 blue:0.50 alpha:1.0])
                                            : (focused ? UIColor.blackColor : UIColor.whiteColor);
    self.symbolView.tintColor = foreground;
    self.titleLabel.textColor = foreground;
    self.stateLabel.textColor = UIColor.whiteColor;
    self.layer.zPosition = focused ? 1.0 : 0.0;
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    [coordinator addCoordinatedAnimations:^{
        [self updateAppearance];
    } completion:nil];
}

@end

@implementation BrowserAdvancedMenuSection

+ (instancetype)sectionWithTitle:(NSString *)title items:(NSArray<BrowserAdvancedMenuItem *> *)items {
    BrowserAdvancedMenuSection *section = [BrowserAdvancedMenuSection new];
    section.title = title ?: @"";
    section.items = [items copy] ?: @[];
    return section;
}

@end

@interface BrowserAdvancedMenuViewController : UIViewController <UICollectionViewDataSource, UICollectionViewDelegateFlowLayout>

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
@property (nonatomic) UICollectionView *tileView;
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
    NSURL *displayURL = [NSURL URLWithString:self.addressText ?: @""];
    NSString *displayDomain = displayURL.host;
    addressLabel.text = displayDomain.length > 0 ? displayDomain : @"Search or enter address";
    addressLabel.font = [UIFont systemFontOfSize:25.0 weight:UIFontWeightMedium];
    addressLabel.textColor = UIColor.whiteColor;
    addressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    addressLabel.userInteractionEnabled = NO;
    [addressButton addSubview:addressLabel];

    UIStackView *navigationToolbar = [UIStackView new];
    navigationToolbar.translatesAutoresizingMaskIntoConstraints = NO;
    navigationToolbar.axis = UILayoutConstraintAxisHorizontal;
    navigationToolbar.alignment = UIStackViewAlignmentFill;
    navigationToolbar.distribution = UIStackViewDistributionFill;
    navigationToolbar.spacing = 8.0;
    [panelView.contentView addSubview:navigationToolbar];
    NSArray<NSString *> *toolbarSymbols = @[@"house.fill", @"arrow.clockwise", @"plus", @"square.on.square"];
    NSMutableArray<UIButton *> *toolbarButtons = [NSMutableArray arrayWithCapacity:self.toolbarItems.count];
    [self.toolbarItems enumerateObjectsUsingBlock:^(BrowserAdvancedMenuItem *item, NSUInteger index, __unused BOOL *stop) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = 10000 + (NSInteger)index;
        button.enabled = item.enabled;
        button.backgroundColor = item.toggleStateProvider != nil && item.toggleStateProvider()
            ? [UIColor colorWithRed:0.20 green:0.54 blue:0.90 alpha:0.72]
            : [UIColor colorWithWhite:1.0 alpha:0.12];
        button.layer.cornerRadius = 12.0;
        UIImageSymbolConfiguration *symbolConfiguration = [UIImageSymbolConfiguration configurationWithPointSize:34.0
                                                                                                           weight:UIImageSymbolWeightMedium];
        UIImage *symbol = [UIImage systemImageNamed:toolbarSymbols[index] withConfiguration:symbolConfiguration];
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
        button.accessibilityLabel = item.title;
        button.accessibilityValue = item.toggleStateProvider != nil ? (item.toggleStateProvider() ? @"On" : @"Off") : nil;
        [button addTarget:self action:@selector(toolbarButtonPressed:) forControlEvents:UIControlEventPrimaryActionTriggered];
        if (index == kBrowserNavigationToolbarItemCount - 2) {
            [navigationToolbar addArrangedSubview:addressButton];
        }
        [navigationToolbar addArrangedSubview:button];
        [button.widthAnchor constraintEqualToConstant:58.0].active = YES;
        [toolbarButtons addObject:button];
    }];
    self.toolbarButtons = toolbarButtons;

    UIView *toolbarSeparator = [UIView new];
    toolbarSeparator.translatesAutoresizingMaskIntoConstraints = NO;
    toolbarSeparator.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.24];
    [panelView.contentView addSubview:toolbarSeparator];

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

    UICollectionViewFlowLayout *tileLayout = [UICollectionViewFlowLayout new];
    tileLayout.itemSize = CGSizeMake((self.panelWidth - 32.0 - 40.0 - 12.0) / 2.0, 132.0);
    tileLayout.minimumInteritemSpacing = 12.0;
    tileLayout.minimumLineSpacing = 14.0;
    tileLayout.sectionInset = UIEdgeInsetsMake(4.0, 20.0, 22.0, 20.0);
    tileLayout.headerReferenceSize = CGSizeMake(self.panelWidth - 32.0, 48.0);

    UICollectionView *tileView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:tileLayout];
    tileView.translatesAutoresizingMaskIntoConstraints = NO;
    tileView.dataSource = self;
    tileView.delegate = self;
    tileView.backgroundColor = UIColor.clearColor;
    tileView.remembersLastFocusedIndexPath = YES;
    tileView.showsVerticalScrollIndicator = NO;
    tileView.contentInset = UIEdgeInsetsZero;
    if (@available(tvOS 11.0, *)) {
        tileView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [tileView registerClass:BrowserAdvancedMenuTileCell.class forCellWithReuseIdentifier:@"MenuTile"];
    [tileView registerClass:UICollectionReusableView.class
        forSupplementaryViewOfKind:UICollectionElementKindSectionHeader
               withReuseIdentifier:@"MenuSectionHeader"];
    [panelView.contentView addSubview:tileView];
    self.tileView = tileView;

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

        [addressButton.heightAnchor constraintEqualToConstant:64.0],
        [addressButton.widthAnchor constraintGreaterThanOrEqualToConstant:120.0],
        [addressIcon.leadingAnchor constraintEqualToAnchor:addressButton.leadingAnchor constant:18.0],
        [addressIcon.centerYAnchor constraintEqualToAnchor:addressButton.centerYAnchor],
        [addressIcon.widthAnchor constraintEqualToConstant:32.0],
        [addressIcon.heightAnchor constraintEqualToConstant:32.0],
        [addressLabel.leadingAnchor constraintEqualToAnchor:addressIcon.trailingAnchor constant:14.0],
        [addressLabel.trailingAnchor constraintEqualToAnchor:addressButton.trailingAnchor constant:-18.0],
        [addressLabel.centerYAnchor constraintEqualToAnchor:addressButton.centerYAnchor],

        [navigationToolbar.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:24.0],
        [navigationToolbar.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-24.0],
        [navigationToolbar.topAnchor constraintEqualToAnchor:panelView.topAnchor constant:24.0],
        [navigationToolbar.heightAnchor constraintEqualToConstant:64.0],

        [toolbarSeparator.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:32.0],
        [toolbarSeparator.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-32.0],
        [toolbarSeparator.topAnchor constraintEqualToAnchor:navigationToolbar.bottomAnchor constant:14.0],
        [toolbarSeparator.heightAnchor constraintEqualToConstant:1.0],

        [tileView.topAnchor constraintEqualToAnchor:toolbarSeparator.bottomAnchor constant:12.0],
        [tileView.leadingAnchor constraintEqualToAnchor:panelView.leadingAnchor constant:16.0],
        [tileView.trailingAnchor constraintEqualToAnchor:panelView.trailingAnchor constant:-16.0],
        [tileView.bottomAnchor constraintEqualToAnchor:footerLabel.topAnchor constant:-8.0],

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

- (NSInteger)numberOfSectionsInCollectionView:(__unused UICollectionView *)collectionView {
    return (NSInteger)self.sections.count;
}

- (NSInteger)collectionView:(__unused UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return (NSInteger)self.sections[(NSUInteger)section].items.count;
}

- (CGSize)collectionView:(__unused UICollectionView *)collectionView
                  layout:(__unused UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat availableWidth = self.panelWidth - 32.0 - 40.0;
    BOOL isZoomRow = indexPath.section == 0 && indexPath.item < 3;
    CGFloat width = isZoomRow ? floor((availableWidth - 24.0) / 3.0) - 1.0
                              : floor((availableWidth - 12.0) / 2.0) - 1.0;
    return CGSizeMake(width, 132.0);
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    BrowserAdvancedMenuTileCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"MenuTile"
                                                                                    forIndexPath:indexPath];
    BrowserAdvancedMenuItem *item = self.sections[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.item];
    [cell configureWithItem:item];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView
           viewForSupplementaryElementOfKind:(NSString *)kind
                                 atIndexPath:(NSIndexPath *)indexPath {
    UICollectionReusableView *header = [collectionView dequeueReusableSupplementaryViewOfKind:kind
                                                                           withReuseIdentifier:@"MenuSectionHeader"
                                                                                  forIndexPath:indexPath];
    UILabel *titleLabel = [header viewWithTag:9191];
    if (titleLabel == nil) {
        titleLabel = [UILabel new];
        titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        titleLabel.tag = 9191;
        titleLabel.font = [UIFont systemFontOfSize:21.0 weight:UIFontWeightSemibold];
        titleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.72];
        [header addSubview:titleLabel];
        [NSLayoutConstraint activateConstraints:@[
            [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:20.0],
            [titleLabel.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-20.0],
            [titleLabel.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-4.0],
        ]];
    }
    titleLabel.text = self.sections[(NSUInteger)indexPath.section].title.uppercaseString;
    return header;
}

- (BOOL)collectionView:(__unused UICollectionView *)collectionView
 canFocusItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.sections[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.item].enabled;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [collectionView deselectItemAtIndexPath:indexPath animated:YES];
    BrowserAdvancedMenuItem *item = self.sections[(NSUInteger)indexPath.section].items[(NSUInteger)indexPath.item];
    BrowserAdvancedMenuItemHandler handler = item.handler;
    if (item.toggleStateProvider != nil || item.keepsMenuOpen) {
        if (handler != nil) {
            handler();
        }
        if (item.toggleStateProvider != nil) {
            BrowserAdvancedMenuTileCell *cell = (BrowserAdvancedMenuTileCell *)[collectionView cellForItemAtIndexPath:indexPath];
            [cell configureWithItem:item];
        }
        return;
    }
    [self dismissMenuWithCompletion:handler];
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
    if (self.toolbarButtons.count >= kBrowserNavigationToolbarItemCount) {
        UIButton *newTabButton = self.toolbarButtons[kBrowserNavigationToolbarItemCount - 2];
        if (newTabButton.enabled) {
            return @[newTabButton];
        }
    }
    if (self.addressButton.enabled) {
        return @[self.addressButton];
    }
    for (UIButton *button in self.toolbarButtons) {
        if (button.enabled) {
            return @[button];
        }
    }
    return @[self.tileView];
}

- (void)didUpdateFocusInContext:(UIFocusUpdateContext *)context
       withAnimationCoordinator:(UIFocusAnimationCoordinator *)coordinator {
    [super didUpdateFocusInContext:context withAnimationCoordinator:coordinator];
    UIView *previousView = context.previouslyFocusedView;
    UIView *nextView = context.nextFocusedView;
    if (previousView == self.addressButton) {
        previousView.layer.zPosition = 0.0;
        ((UILabel *)[self.addressButton viewWithTag:9898]).textColor = UIColor.whiteColor;
        [self setToolbarIconColor:UIColor.whiteColor forButton:self.addressButton];
    }
    if (nextView == self.addressButton) {
        [nextView.superview bringSubviewToFront:nextView];
        nextView.layer.zPosition = 2.0;
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

- (void)saveFavoritesArray:(NSArray *)favorites {
    [[BrowserHistoryStore sharedStore] saveFavorites:favorites];
    [self.host browserRefreshNewTabPageSelectingGroup:@"favorites" index:0];
}

- (NSArray *)storedEntryForKind:(NSString *)kind index:(NSUInteger)index {
    NSArray *entries = [kind isEqualToString:@"favorite"] ? [[BrowserHistoryStore sharedStore] favorites] : @[];
    if (index >= entries.count || ![entries[index] isKindOfClass:[NSArray class]]) {
        return nil;
    }
    return entries[index];
}

- (void)presentEditFavoriteAtIndex:(NSUInteger)index title:(NSString *)title URLString:(NSString *)URLString {
    BrowserFavoriteEditorViewController *editor = [[BrowserFavoriteEditorViewController alloc]
                                                    initWithTitle:title URLString:URLString];
    __weak typeof(self) weakSelf = self;
    editor.saveHandler = ^NSString *(NSString *rawTitle, NSString *rawURL) {
        NSString *enteredTitle = [rawTitle stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        NSString *enteredURL = [rawURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if ([enteredURL rangeOfString:@"://"].location == NSNotFound) {
            enteredURL = [@"https://" stringByAppendingString:enteredURL];
        }
        NSURLComponents *components = [NSURLComponents componentsWithString:enteredURL];
        NSString *scheme = components.scheme.lowercaseString;
        if (components.host.length == 0 || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
            return @"Enter a valid http or https address.";
        }
        NSMutableArray *favorites = [[[BrowserHistoryStore sharedStore] favorites] mutableCopy];
        if (index >= favorites.count) {
            return @"This favorite is no longer available.";
        }
        NSString *savedTitle = enteredTitle.length > 0 ? enteredTitle : components.host;
        favorites[index] = @[components.URL.absoluteString ?: enteredURL, savedTitle ?: @""];
        [[BrowserHistoryStore sharedStore] saveFavorites:favorites];
        [weakSelf.host browserRefreshNewTabPageSelectingGroup:@"favorites" index:index];
        return nil;
    };
    editor.deleteHandler = ^{
        NSMutableArray *favorites = [[[BrowserHistoryStore sharedStore] favorites] mutableCopy];
        if (index >= favorites.count) {
            return;
        }
        [favorites removeObjectAtIndex:index];
        [[BrowserHistoryStore sharedStore] saveFavorites:favorites];
        [weakSelf.host browserRefreshNewTabPageSelectingGroup:@"favorites" index:index];
    };
    [self.host browserPresentViewController:editor];
}

- (void)presentStoredItemActionsForKind:(NSString *)kind index:(NSUInteger)index {
    if (![kind isEqualToString:@"favorite"]) {
        return;
    }
    NSArray *entry = [self storedEntryForKind:kind index:index];
    if (entry == nil || entry.count == 0 || ![entry[0] isKindOfClass:[NSString class]]) {
        return;
    }
    NSString *URLString = entry[0];
    NSString *title = entry.count > 1 && [entry[1] isKindOfClass:[NSString class]] ? entry[1] : @"";
    [self presentEditFavoriteAtIndex:index title:title URLString:URLString];
}

- (void)presentAllHistory {
    BrowserHistoryViewController *controller = [BrowserHistoryViewController new];
    __weak typeof(self) weakSelf = self;
    controller.historyDidChange = ^{
        [weakSelf.host browserRefreshNewTabPageSelectingGroup:@"history" index:0];
    };
    controller.openURLString = ^(NSString *URLString) {
        [weakSelf.host browserOpenHistoryURLString:URLString];
    };
    [self.host browserPresentViewController:controller];
}

- (void)deleteHistoryForURLString:(NSString *)URLString {
    [[BrowserHistoryStore sharedStore] deleteVisitsForURLString:URLString];
    [self.host browserRefreshNewTabPageSelectingGroup:@"history" index:0];
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
        NSMutableArray *favorites = [[[BrowserHistoryStore sharedStore] favorites] mutableCopy];
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

- (void)setPageZoomPercent:(NSUInteger)percent {
    BrowserWebView *webView = self.host.browserWebView;
    UIScrollView *scrollView = webView.scrollView;
    CGFloat previousZoom = self.preferencesStore.pageZoomPercent / 100.0;
    CGFloat visibleWidth = CGRectGetWidth(scrollView.bounds);
    CGFloat centerX = scrollView.contentOffset.x + visibleWidth / 2.0;

    self.preferencesStore.pageZoomPercent = percent;
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
    BrowserAdvancedMenuItem *newTabItem = [self advancedMenuItemWithTitle:@"New Tab"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^{
        [self.host browserCreateNewTab];
    }];
    BrowserAdvancedMenuItem *tabsItem = [self advancedMenuItemWithTitle:@"Tabs"
                                                                 style:UIAlertActionStyleDefault
                                                               handler:^{
        [self.host browserShowTabOverview];
    }];
    return @[homeItem, reloadItem, newTabItem, tabsItem];
}

- (BrowserAdvancedMenuItem *)tileItem:(BrowserAdvancedMenuItem *)item
                                title:(NSString *)title
                               symbol:(NSString *)symbol {
    item.tileTitle = title;
    item.tileSymbolName = symbol;
    return item;
}

- (void)presentDebugOptions {
    UIAlertController *menu = [self browserAlertControllerWithTitle:@"Debug" message:nil];
    [menu addAction:[self browserActionWithTitle:@"Media Diagnostics"
                                       style:UIAlertActionStyleDefault
                                     handler:^(__unused UIAlertAction *action) {
        [self presentMediaDiagnostics];
    }]];
    [menu addAction:[self browserActionWithTitle:@"Inspect WebKit Media Prefs"
                                       style:UIAlertActionStyleDefault
                                     handler:^(__unused UIAlertAction *action) {
        [self presentWebKitRuntimeMediaPreferences];
    }]];
    [menu addAction:[self browserCancelAction]];
    [self.host browserPresentViewController:menu];
}

- (NSArray<BrowserAdvancedMenuSection *> *)advancedMenuSections {
    BrowserAdvancedMenuItem *addFavoriteItem = [self advancedMenuItemWithTitle:@"Add to Favorites"
                                                                         style:UIAlertActionStyleDefault
                                                                       handler:^{
        [self presentAddFavoritePrompt];
    }];
    BrowserAdvancedMenuItem *historyItem = [self advancedMenuItemWithTitle:@"Recents"
                                                                     style:UIAlertActionStyleDefault
                                                                   handler:^{
        [self.host browserShowNewTabPageSelectingGroup:@"history"];
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
    BrowserAdvancedMenuItem *debugItem = [self advancedMenuItemWithTitle:@"Debug"
                                                                   style:UIAlertActionStyleDefault
                                                                 handler:^{
        [self presentDebugOptions];
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
        [BrowserAdvancedMenuSection sectionWithTitle:@"Quick Actions"
                                               items:@[
            [self tileItem:zoomOutItem title:@"Zoom Out" symbol:@"minus.magnifyingglass"],
            [self tileItem:zoomResetItem title:@"Reset Zoom" symbol:@"arrow.counterclockwise"],
            [self tileItem:zoomInItem title:@"Zoom In" symbol:@"plus.magnifyingglass"],
            [self tileItem:addFavoriteItem title:@"Add Favorite" symbol:@"star.fill"],
            [self tileItem:historyItem title:@"Recents" symbol:@"clock.arrow.circlepath"],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Settings"
                                               items:@[
            [self tileItem:[self adBlockToggleMenuItem] title:@"Ad Block" symbol:@"hand.raised.fill"],
            [self tileItem:[self cursorMagnifierToggleMenuItem] title:@"Magnifier" symbol:@"magnifyingglass"],
            [self tileItem:[self fullscreenVideoPlaybackToggleMenuItem] title:@"Full Screen Player" symbol:@"play.rectangle.fill"],
            [self tileItem:[self userAgentModeMenuItem] title:@"Mobile Site" symbol:@"iphone"],
        ]],
        [BrowserAdvancedMenuSection sectionWithTitle:@"Tools"
                                               items:@[
            [self tileItem:debugItem title:@"Debug" symbol:@"ladybug"],
            [self tileItem:[self usageGuideMenuItem] title:@"User Guide" symbol:@"book.closed.fill"],
            [self tileItem:clearCacheItem title:@"Clear Cache" symbol:@"externaldrive"],
            [self tileItem:clearCookiesItem title:@"Clear Cookies" symbol:@"trash"],
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
