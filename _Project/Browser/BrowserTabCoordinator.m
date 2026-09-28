#import "BrowserTabCoordinator.h"

#import "BrowserNavigationService.h"
#import "BrowserHistoryStore.h"
#import "BrowserPreferencesStore.h"
#import "BrowserSessionStore.h"
#import "BrowserTabViewModel.h"
#import "BrowserTopBarView.h"
#import "BrowserViewModel.h"
#import "BrowserWebView.h"

static CGFloat const kThumbnailStagingOffset = 4096.0;
static NSString * const kBrowserNewTabURL = @"about:blank";

static NSString *BrowserNewTabEscape(NSString *value) {
    NSString *escaped = [value isKindOfClass:[NSString class]] ? value : @"";
    escaped = [escaped stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
    escaped = [escaped stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return [escaped stringByReplacingOccurrencesOfString:@"'" withString:@"&#39;"];
}

static NSString *BrowserNewTabSectionHTML(NSArray *entries, BOOL favorites, NSUInteger limit) {
    NSMutableString *cards = [NSMutableString string];
    NSUInteger count = 0;
    NSUInteger storageIndex = 0;
    for (id rawEntry in entries) {
        NSUInteger entryIndex = storageIndex++;
        if (![rawEntry isKindOfClass:[NSArray class]]) {
            continue;
        }
        NSArray *entry = rawEntry;
        NSString *URLString = entry.count > 0 && [entry[0] isKindOfClass:[NSString class]] ? entry[0] : @"";
        NSURL *URL = [NSURL URLWithString:URLString];
        NSString *scheme = URL.scheme.lowercaseString;
        if (URL.host.length == 0 || !([scheme isEqualToString:@"https"] || [scheme isEqualToString:@"http"])) {
            continue;
        }
        NSString *storedTitle = entry.count > 1 && [entry[1] isKindOfClass:[NSString class]] ? entry[1] : @"";
        NSString *displayTitle = storedTitle.length > 0 ? storedTitle : URL.host;
        NSString *monogram = [URL.host.uppercaseString substringToIndex:1];
        if (favorites) {
            [cards appendFormat:@"<div class='tile-wrap'><a class='tile nav-target' href='%@'><span class='tile-icon'>%@</span><span class='tile-title'>%@</span></a><a class='manage-button' href='tvosbrowser://manage?kind=favorite&amp;index=%lu' aria-label='Edit favorite'>✎</a></div>",
                BrowserNewTabEscape(URLString), BrowserNewTabEscape(monogram), BrowserNewTabEscape(displayTitle),
                (unsigned long)entryIndex];
        } else {
            NSURLComponents *deleteURL = [NSURLComponents new];
            deleteURL.scheme = @"tvosbrowser";
            deleteURL.host = @"delete-history";
            deleteURL.queryItems = @[[NSURLQueryItem queryItemWithName:@"url" value:URLString]];
            NSUInteger visits = entry.count > 2 ? [entry[2] unsignedIntegerValue] : 1;
            [cards appendFormat:@"<div class='history-wrap'><a class='history-row nav-target' href='%@'><span class='history-icon'>%@</span><span class='history-text'><strong>%@</strong><small>%@ · %lu visits</small></span></a><a class='history-delete' href='%@' aria-label='Delete history entry'>Delete</a></div>",
                BrowserNewTabEscape(URLString), BrowserNewTabEscape(monogram),
                BrowserNewTabEscape(displayTitle), BrowserNewTabEscape(URL.host), (unsigned long)visits,
                BrowserNewTabEscape(deleteURL.URL.absoluteString)];
        }
        if (++count >= limit) {
            break;
        }
    }
    if (count == 0) {
        [cards appendFormat:@"<p class='empty'>%@</p>", favorites ? @"Saved pages will appear here." : @"Visited pages will appear here."];
    }
    NSString *footer = favorites ? @"" : @"<a id='all-history' class='all-history nav-target' href='tvosbrowser://history'>All History  →</a>";
    return [NSString stringWithFormat:@"<section id='%@'><div class='section-heading'><h2>%@</h2><span class='count'>%lu</span><span class='section-hint'>%@</span></div><div class='%@'>%@</div>%@</section>",
        favorites ? @"favorites" : @"history", favorites ? @"Favorites" : @"History",
        (unsigned long)count, favorites ? @"Play/Pause to edit" : @"Most visited", favorites ? @"tiles" : @"history-list", cards, footer];
}

@interface BrowserTabCoordinator ()

@property (nonatomic, weak) id<BrowserTabCoordinatorHost> host;
@property (nonatomic) BrowserViewModel *viewModel;
@property (nonatomic) BrowserPreferencesStore *preferencesStore;
@property (nonatomic) BrowserNavigationService *navigationService;
@property (nonatomic) BrowserSessionStore *sessionStore;
@property (nonatomic, weak) UIView *browserContainerView;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, weak) BrowserTopBarView *topMenuView;
@property (nonatomic, weak) UIImageView *cursorView;
@property (nonatomic, weak) UIPanGestureRecognizer *manualScrollPanRecognizer;
@property (nonatomic, weak) id webViewDelegate;
@property (nonatomic) BOOL scrollViewAllowBounces;
@property (nonatomic) NSMutableDictionary<NSString *, BrowserWebView *> *webViewsByTabIdentifier;
@property (nonatomic) UIView *thumbnailStagingView;
@property (nonatomic, readwrite, nullable) BrowserWebView *activeWebView;
@property (nonatomic, copy) NSString *pendingNewTabSelectionGroup;
@property (nonatomic) NSUInteger pendingNewTabSelectionIndex;
@property (nonatomic, readwrite) NSUInteger newTabPageGeneration;

- (void)showNewTabPageInWebView:(BrowserWebView *)webView tab:(BrowserTabViewModel *)tab;

@end

@implementation BrowserTabCoordinator

- (instancetype)initWithHost:(id<BrowserTabCoordinatorHost>)host
                   viewModel:(BrowserViewModel *)viewModel
            preferencesStore:(BrowserPreferencesStore *)preferencesStore
           navigationService:(BrowserNavigationService *)navigationService
                sessionStore:(BrowserSessionStore *)sessionStore
          browserContainerView:(UIView *)browserContainerView
                    rootView:(UIView *)rootView
                  topMenuView:(BrowserTopBarView *)topMenuView
                  cursorView:(UIImageView *)cursorView
     manualScrollPanRecognizer:(UIPanGestureRecognizer *)manualScrollPanRecognizer
             webViewDelegate:(id)webViewDelegate
         scrollViewAllowBounces:(BOOL)scrollViewAllowBounces {
    self = [super init];
    if (self) {
        _host = host;
        _viewModel = viewModel;
        _preferencesStore = preferencesStore;
        _navigationService = navigationService;
        _sessionStore = sessionStore;
        _browserContainerView = browserContainerView;
        _rootView = rootView;
        _topMenuView = topMenuView;
        _cursorView = cursorView;
        _manualScrollPanRecognizer = manualScrollPanRecognizer;
        _webViewDelegate = webViewDelegate;
        _scrollViewAllowBounces = scrollViewAllowBounces;
        _webViewsByTabIdentifier = [NSMutableDictionary dictionary];
        [_preferencesStore ensureUserAgentConsistency];
        [self ensureThumbnailStagingView];
    }
    return self;
}

- (BrowserTabViewModel *)activeTab {
    return [self.viewModel activeTab];
}

- (NSString *)requestURL {
    return self.activeTab.requestURL;
}

- (void)setRequestURL:(NSString *)requestURL {
    self.activeTab.requestURL = requestURL ?: @"";
}

- (NSString *)previousURL {
    return self.activeTab.previousURL;
}

- (void)setPreviousURL:(NSString *)previousURL {
    self.activeTab.previousURL = previousURL ?: @"";
}

- (BOOL)topNavigationVisible {
    return self.viewModel.topNavigationBarVisible;
}

- (CGFloat)topMenuBrowserOffset {
    return self.topNavigationVisible ? self.topMenuView.frame.size.height : 0.0;
}

- (void)setTopNavigationVisible:(BOOL)visible {
    self.viewModel.topNavigationBarVisible = visible;
    self.topMenuView.hidden = !visible;
    [self updateTopNavAndWebView];
}

- (void)updateTopNavAndWebView {
    if (self.activeWebView == nil) {
        return;
    }
    if (self.topNavigationVisible) {
        self.activeWebView.frame = CGRectMake(self.rootView.bounds.origin.x,
                                              self.rootView.bounds.origin.y + self.topMenuBrowserOffset,
                                              self.rootView.bounds.size.width,
                                              self.rootView.bounds.size.height - self.topMenuBrowserOffset);
    } else {
        self.activeWebView.frame = self.rootView.bounds;
    }
}

- (CGSize)thumbnailViewportSize {
    CGFloat width = CGRectGetWidth(self.rootView.bounds);
    CGFloat height = CGRectGetHeight(self.rootView.bounds) - self.topMenuBrowserOffset;
    return CGSizeMake(MAX(width, 1.0), MAX(height, 1.0));
}

- (void)ensureThumbnailStagingView {
    if (self.thumbnailStagingView != nil || self.rootView == nil) {
        return;
    }

    CGSize viewportSize = [self thumbnailViewportSize];
    UIView *stagingView = [[UIView alloc] initWithFrame:CGRectMake(kThumbnailStagingOffset,
                                                                   0.0,
                                                                   viewportSize.width,
                                                                   viewportSize.height)];
    stagingView.backgroundColor = UIColor.clearColor;
    stagingView.userInteractionEnabled = NO;
    stagingView.clipsToBounds = YES;
    [self.rootView addSubview:stagingView];
    self.thumbnailStagingView = stagingView;
}

- (void)updateThumbnailStagingViewFrame {
    [self ensureThumbnailStagingView];
    if (self.thumbnailStagingView == nil) {
        return;
    }

    CGSize viewportSize = [self thumbnailViewportSize];
    self.thumbnailStagingView.frame = CGRectMake(kThumbnailStagingOffset,
                                                 0.0,
                                                 viewportSize.width,
                                                 viewportSize.height);
}

- (void)prepareWebViewLayoutForSnapshot:(BrowserWebView *)webView {
    if (webView == nil) {
        return;
    }

    if (webView.superview == self.thumbnailStagingView) {
        webView.frame = self.thumbnailStagingView.bounds;
    }
    [webView setNeedsLayout];
    [webView layoutIfNeeded];

    UIScrollView *scrollView = webView.scrollView;
    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    [self.rootView setNeedsLayout];
    [self.rootView layoutIfNeeded];
}

- (void)parkWebViewForThumbnailing:(BrowserWebView *)webView {
    if (webView == nil) {
        return;
    }

    [self updateThumbnailStagingViewFrame];
    webView.userInteractionEnabled = NO;
    UIScrollView *scrollView = webView.scrollView;
    scrollView.scrollEnabled = NO;
    scrollView.bounces = self.scrollViewAllowBounces;
    if (webView.superview != self.thumbnailStagingView) {
        [webView removeFromSuperview];
        [self.thumbnailStagingView addSubview:webView];
    }
    webView.frame = self.thumbnailStagingView.bounds;
}

- (BOOL)isWebViewStaged:(BrowserWebView *)webView {
    return webView != nil && webView.superview == self.thumbnailStagingView;
}

- (BrowserWebView *)createConfiguredWebView {
    BrowserWebView *webView = [[BrowserWebView alloc] initWithUserAgent:self.preferencesStore.userAgent
                                            allowsInlineMediaPlayback:YES];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.clipsToBounds = NO;
    webView.delegate = self.webViewDelegate;
    webView.layoutMargins = UIEdgeInsetsZero;
    webView.opaque = NO;
    webView.backgroundColor = UIColor.blackColor;

    UIScrollView *scrollView = webView.scrollView;
    scrollView.layoutMargins = UIEdgeInsetsZero;
    scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    scrollView.contentOffset = CGPointZero;
    scrollView.contentInset = UIEdgeInsetsZero;
    scrollView.clipsToBounds = NO;
    scrollView.backgroundColor = UIColor.blackColor;
    scrollView.bounces = self.scrollViewAllowBounces;
    [scrollView.panGestureRecognizer addTarget:self action:@selector(handleWebViewPanGesture:)];
    scrollView.scrollEnabled = NO;

    BOOL shouldScalePagesToFit = self.preferencesStore.scalePagesToFit;
    webView.scalesPageToFit = shouldScalePagesToFit;
    webView.pageZoomFactor = self.preferencesStore.pageZoomPercent / 100.0;
    webView.textZoomFactor = self.preferencesStore.textFontSize / 100.0;
    webView.contentMode = shouldScalePagesToFit ? UIViewContentModeScaleAspectFit : UIViewContentModeScaleToFill;
    webView.userInteractionEnabled = NO;
    return webView;
}

- (void)refreshActiveTabUI {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil) {
        self.topMenuView.URLLabel.text = @"";
        return;
    }

    self.activeWebView.scalesPageToFit = self.preferencesStore.scalePagesToFit;
    self.activeWebView.pageZoomFactor = self.preferencesStore.pageZoomPercent / 100.0;
    self.activeWebView.textZoomFactor = self.preferencesStore.textFontSize / 100.0;

    NSURLRequest *request = self.activeWebView.request;
    NSString *currentURL = tab.URLString.length > 0 ? tab.URLString : request.URL.absoluteString;
    self.topMenuView.URLLabel.text = currentURL.length > 0 && ![currentURL isEqualToString:kBrowserNewTabURL]
        ? currentURL : @"New Tab";

    if (request != nil) {
        [self.host browserTabCoordinatorUpdateTextFontSize];
    }
}

- (BOOL)restoreBrowserSession {
    return [self.sessionStore restoreSessionIntoViewModel:self.viewModel];
}

- (void)restoreInitialStateOrCreateFirstTab {
    self.topMenuView.hidden = !self.viewModel.topNavigationBarVisible;
    if (![self restoreBrowserSession]) {
        [self createNewTabLoadingHomePage:NO];
        return;
    }
    [self initWebView];
    [self refreshActiveTabUI];
}

- (void)webViewDidAppear {
    NSURLRequest *savedReopenRequest = [self.sessionStore consumeSavedURLToReopenRequestWithNavigationService:self.navigationService];
    if (savedReopenRequest != nil) {
        [self.activeWebView loadRequest:savedReopenRequest];
    } else if (self.activeWebView.request == nil) {
        [self loadStoredContentForTab:self.activeTab webView:self.activeWebView fallbackToHomePage:YES];
    }
}

- (void)loadHomePage {
    NSURLRequest *homePageRequest = [self.navigationService homePageRequest];
    if (homePageRequest != nil) {
        [self.activeWebView loadRequest:homePageRequest];
    }
}


- (void)showNewTabPageInWebView:(BrowserWebView *)webView tab:(BrowserTabViewModel *)tab {
    if (webView == nil || tab == nil) {
        return;
    }
    self.newTabPageGeneration += 1;
    NSString *favorites = BrowserNewTabSectionHTML([[BrowserHistoryStore sharedStore] favorites], YES, 40);
    NSArray *popular = [[BrowserHistoryStore sharedStore] mostVisitedWithLimit:10];
    NSMutableArray *popularEntries = [NSMutableArray arrayWithCapacity:popular.count];
    for (NSDictionary *entry in popular) {
        [popularEntries addObject:@[entry[@"url"], entry[@"title"], entry[@"count"]]];
    }
    NSString *history = BrowserNewTabSectionHTML(popularEntries, NO, 10);
    NSMutableString *HTML = [NSMutableString stringWithString:
        @"<!doctype html><html><head><meta charset='utf-8'><meta name='viewport' content='width=device-width, initial-scale=1'>"
         "<title>New Tab</title><style>"
         ":root{color-scheme:dark;font-family:-apple-system,BlinkMacSystemFont,system-ui,sans-serif}"
         "*{box-sizing:border-box}html{background:#101725}body{margin:0;min-height:100vh;color:#f7f7fb;background:radial-gradient(circle at 12% 8%,#35496b 0,transparent 38%),radial-gradient(circle at 86% 26%,#57416b 0,transparent 40%),linear-gradient(145deg,#101725,#1d2033)}"
         "main{max-width:1760px;margin:0 auto;padding:62px 72px 100px}"
         ".brand{display:flex;justify-content:center;align-items:center;gap:20px;margin:10px 0 72px}"
         ".brand-mark{display:grid;place-items:center;width:74px;height:74px;border-radius:24px;background:linear-gradient(135deg,#ea6c48,#9b4fc4);font-size:44px;font-weight:800}"
         "h1{font-size:54px;line-height:1;margin:0;letter-spacing:-.035em}"
         ".search{display:flex;align-items:center;gap:23px;width:100%;height:102px;padding:0 34px;border-radius:54px;background:linear-gradient(130deg,rgba(255,255,255,.20),rgba(255,255,255,.09));border:1px solid rgba(255,255,255,.28);box-shadow:inset 0 1px rgba(255,255,255,.22),0 18px 45px rgba(0,0,0,.18);-webkit-backdrop-filter:blur(28px);backdrop-filter:blur(28px);color:#e4e6f2;text-decoration:none;font-size:28px}"
         ".search-symbol{font-size:35px;color:#e1e1ed}.search:hover,.search:focus,.search.selected{background:rgba(255,255,255,.87);color:#1a2234;outline:4px solid rgba(186,203,255,.8)}"
         "section{margin-top:62px;padding:30px 32px 34px;border:1px solid rgba(255,255,255,.20);border-radius:32px;background:linear-gradient(145deg,rgba(255,255,255,.13),rgba(255,255,255,.055));box-shadow:inset 0 1px rgba(255,255,255,.18),0 26px 60px rgba(0,0,0,.15);-webkit-backdrop-filter:blur(28px);backdrop-filter:blur(28px)}.section-heading{display:flex;align-items:center;gap:15px;margin-bottom:23px}"
         "h2{font-size:27px;margin:0;font-weight:650}.count,.section-hint{color:#a9a8b7;font-size:20px}.section-hint{margin-left:auto}"
         ".tiles{display:grid;grid-template-columns:repeat(8,minmax(0,1fr));gap:24px}"
         ".tile-wrap,.history-wrap{position:relative;min-width:0}"
         ".tile{display:flex;flex-direction:column;align-items:center;min-width:0;color:#ecebf1;text-decoration:none;text-align:center;border-radius:20px;padding:12px 7px}"
         ".tile-icon{display:grid;place-items:center;width:116px;height:116px;border-radius:24px;background:linear-gradient(140deg,rgba(255,255,255,.25),rgba(255,255,255,.08));border:1px solid rgba(255,255,255,.24);box-shadow:inset 0 1px rgba(255,255,255,.24);color:white;font-size:54px;font-weight:700}"
         ".tile-title{display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2;overflow:hidden;margin-top:13px;font-size:21px;line-height:1.25;max-width:155px}"
         ".tile:hover,.tile:focus,.tile.selected{background:rgba(255,255,255,.82);color:#202337;outline:4px solid rgba(186,203,255,.8);transform:scale(1.035)}.tile:hover .tile-icon,.tile:focus .tile-icon,.tile.selected .tile-icon{background:rgba(65,74,107,.35);color:#172034}"
         ".manage-button{position:absolute;right:3px;top:3px;display:grid;place-items:center;width:42px;height:42px;border-radius:50%;background:#5c5a6c;color:white;text-decoration:none;font-size:23px;font-weight:700;line-height:1}"
         ".manage-button:hover,.manage-button:focus{background:#8680ba;outline:3px solid #c4bafd;transform:scale(1.1)}"
         ".history-list{display:flex;flex-direction:column;gap:9px}"
         ".history-row{display:flex;align-items:center;gap:20px;min-height:79px;padding:11px 144px 11px 22px;border-radius:18px;background:rgba(255,255,255,.10);border:1px solid rgba(255,255,255,.12);color:#f3f2f6;text-decoration:none}"
         ".history-icon{display:grid;place-items:center;flex:none;width:48px;height:48px;border-radius:13px;background:#535265;font-size:25px;font-weight:700}"
         ".history-text{display:flex;flex-direction:column;min-width:0;gap:4px}.history-text strong{font-size:21px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}"
         ".history-text small{font-size:16px;color:#b9b7c6;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}"
         ".history-delete{position:absolute;right:18px;top:14px;padding:12px 20px;border-radius:14px;background:#5c3941;color:#ffd3d7;text-decoration:none;font-size:20px;font-weight:650}"
         ".history-delete:hover,.history-delete:focus,.history-delete.selected{background:#b44254;color:white;outline:3px solid #ff9cac}"
         ".history-row:hover,.history-row:focus,.history-row.selected{background:rgba(255,255,255,.88);color:#1b2232;outline:4px solid rgba(186,203,255,.8)}.history-row:hover small,.history-row:focus small,.history-row.selected small{color:#414b5f}.history-row:hover .history-icon,.history-row:focus .history-icon,.history-row.selected .history-icon{background:#c3cde2;color:#243047}"
         ".all-history{display:block;width:max-content;margin-top:22px;padding:16px 25px;border-radius:16px;background:rgba(255,255,255,.13);border:1px solid rgba(255,255,255,.22);color:white;text-decoration:none;font-size:22px;font-weight:650}"
         ".all-history:hover,.all-history:focus,.all-history.selected{background:rgba(255,255,255,.86);color:#1b2232;outline:3px solid rgba(186,203,255,.8)}"
         ".empty{color:#aaa8b6;font-size:21px;margin:0;padding:18px 4px}"
         "@media(max-width:1450px){.tiles{grid-template-columns:repeat(6,minmax(0,1fr))}}"
         "@media(max-width:1000px){main{padding:45px 35px}.tiles{grid-template-columns:repeat(4,minmax(0,1fr))}}"
         "</style></head><body><main><div class='brand'><span class='brand-mark'>◆</span><h1>New Tab</h1></div>"
         "<a class='search nav-target selected' id='search' href='tvosbrowser://search'><span class='search-symbol'>⌕</span>Search or enter an address</a>"];
    [HTML appendString:favorites];
    [HTML appendString:history];
    [HTML appendString:@"<script>(function(){let group='search',index=0;const search=document.getElementById('search');"
                       "const favorites=Array.from(document.querySelectorAll('#favorites .nav-target'));"
                       "const history=Array.from(document.querySelectorAll('#history .history-row'));"
                       "const historyDeletes=Array.from(document.querySelectorAll('#history .history-delete'));"
                       "const allHistory=document.getElementById('all-history');"
                       "function current(){if(group==='search')return search;if(group==='favorites')return favorites[index];"
                       "if(group==='history-delete')return historyDeletes[index];if(group==='history-all')return allHistory;return history[index]}"
                       "function select(g,i){let old=current();if(old)old.classList.remove('selected');group=g;index=i;let item=current();"
                       "if(item){item.classList.add('selected');item.scrollIntoView({block:'nearest',inline:'nearest'})}}"
                       "window.browserNewTabNavigate=function(d){if(group==='search'){if(d==='down')select(favorites.length?'favorites':history.length?'history':'history-all',0)}"
                       "else if(group==='favorites'){if(d==='left')select(group,Math.max(0,index-1));else if(d==='right')select(group,Math.min(favorites.length-1,index+1));"
                       "else if(d==='up')select('search',0);else if(d==='down')select(history.length?'history':'history-all',0)}"
                       "else if(group==='history'||group==='history-delete'){if(d==='up')select(index>0?group:favorites.length?'favorites':'search',index>0?index-1:0);"
                       "else if(d==='down')select(index<history.length-1?group:'history-all',index<history.length-1?index+1:0);"
                       "else if(d==='left'&&group==='history-delete')select('history',index);"
                       "else if(d==='left'&&favorites.length)select('favorites',Math.min(index,favorites.length-1));"
                       "else if(d==='right')select('history-delete',index)}"
                       "else if(group==='history-all'&&d==='up')select(history.length?'history':favorites.length?'favorites':'search',history.length?history.length-1:0);return true};"
                       "window.browserNewTabActivate=function(){let item=current();if(item)item.click();return true};"
                       "window.browserNewTabManageSelected=function(){let item=current();if(!item||group!=='favorites')return false;"
                       "let button=item.parentElement.querySelector('.manage-button');if(!button)return false;button.click();return true};"
                       "window.browserNewTabManageAt=function(x,y){let item=document.elementFromPoint(x,y);"
                       "let tile=item&&item.closest('.tile-wrap');let button=tile&&tile.querySelector('.manage-button');"
                       "if(!button)return false;button.click();return true};"
                       "window.browserNewTabSelect=function(g,i){let list=g==='favorites'?favorites:history;if(!list.length){if(g==='history')select('history-all',0);return false;}"
                       "select(g,Math.min(Math.max(i,0),list.length-1));return true};"
                       "})();</script></main></body></html>"];
    tab.title = @"New Tab";
    tab.URLString = kBrowserNewTabURL;
    tab.requestURL = kBrowserNewTabURL;
    [webView loadHTMLString:HTML];
    if (tab == self.activeTab) {
        [self refreshActiveTabUI];
    }
}

- (void)refreshNewTabPageIfVisibleSelectingGroup:(NSString *)group index:(NSUInteger)index {
    if (self.activeWebView == nil || ![self.activeTab.URLString isEqualToString:kBrowserNewTabURL]) {
        return;
    }
    self.pendingNewTabSelectionGroup = [group copy];
    self.pendingNewTabSelectionIndex = index;
    [self showNewTabPageInWebView:self.activeWebView tab:self.activeTab];
}

- (void)showNewTabPageSelectingGroup:(NSString *)group {
    if ([self.activeTab.URLString isEqualToString:kBrowserNewTabURL]) {
        NSString *script = [NSString stringWithFormat:@"window.browserNewTabSelect && window.browserNewTabSelect('%@', 0)", group];
        [self.activeWebView evaluateJavaScript:script completion:^(__unused NSString *result) {}];
        return;
    }
    self.pendingNewTabSelectionGroup = [group copy];
    self.pendingNewTabSelectionIndex = 0;
    [self createNewTabLoadingHomePage:NO];
}

- (void)initWebView {
    self.topMenuView.hidden = !self.viewModel.topNavigationBarVisible;

    BrowserTabViewModel *tab = [self.viewModel ensureActiveTab];
    if (tab == nil) {
        return;
    }

    BrowserWebView *webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil) {
        webView = [self createConfiguredWebView];
        self.webViewsByTabIdentifier[tab.identifier] = webView;
    }
    self.activeWebView = webView;
    [self attachActiveWebView];
}

- (void)attachActiveWebView {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil) {
        return;
    }

    BrowserWebView *activeWebView = self.webViewsByTabIdentifier[tab.identifier];
    if (activeWebView == nil) {
        return;
    }

    [self updateThumbnailStagingViewFrame];
    for (BrowserTabViewModel *candidate in self.viewModel.tabs) {
        BrowserWebView *candidateWebView = self.webViewsByTabIdentifier[candidate.identifier];
        if (candidateWebView == nil || candidateWebView == activeWebView) {
            continue;
        }
        [self parkWebViewForThumbnailing:candidateWebView];
    }

    self.activeWebView = activeWebView;
    [self.topMenuView.loadingSpinner stopAnimating];
    [self.activeWebView removeFromSuperview];
    [self.browserContainerView addSubview:self.activeWebView];
    [self updateTopNavAndWebView];

    UIScrollView *scrollView = self.activeWebView.scrollView;
    [scrollView setNeedsLayout];
    [scrollView layoutIfNeeded];
    [self.rootView setNeedsLayout];
    [self.rootView layoutIfNeeded];
    scrollView.bounces = self.scrollViewAllowBounces;

    BOOL shouldAllowWebInteraction = ![self.host browserTabCoordinatorIsCursorModeEnabled] &&
        ![self.host browserTabCoordinatorIsTabOverviewVisible];
    scrollView.scrollEnabled = shouldAllowWebInteraction;
    self.activeWebView.userInteractionEnabled = shouldAllowWebInteraction;
    self.manualScrollPanRecognizer.enabled = shouldAllowWebInteraction;

    [self refreshActiveTabUI];
}

- (void)updateStoredScrollOffsetForTab:(BrowserTabViewModel *)tab {
    if (tab == nil) {
        return;
    }

    BrowserWebView *webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil) {
        return;
    }

    UIScrollView *scrollView = webView.scrollView;
    tab.savedScrollOffset = scrollView.contentOffset;
    tab.hasSavedScrollOffset = YES;
}

- (void)persistSession {
    for (BrowserTabViewModel *tab in self.viewModel.tabs) {
        [self updateStoredScrollOffsetForTab:tab];
    }
    [self.sessionStore saveSessionForViewModel:self.viewModel];
}

- (void)loadStoredContentForTab:(BrowserTabViewModel *)tab
                        webView:(BrowserWebView *)webView
             fallbackToHomePage:(BOOL)fallbackToHomePage {
    if (webView == nil) {
        return;
    }

    NSString *URLString = tab.URLString.length > 0 ? tab.URLString : tab.requestURL;
    if (URLString.length == 0 || [URLString isEqualToString:kBrowserNewTabURL]) {
        if (fallbackToHomePage) {
            [self showNewTabPageInWebView:webView tab:tab];
        }
        return;
    }

    NSURLRequest *request = [self.navigationService requestForURLString:URLString];
    if (request != nil) {
        [webView loadRequest:request];
    } else if (fallbackToHomePage) {
        NSURLRequest *homePageRequest = [self.navigationService homePageRequest];
        if (homePageRequest != nil) {
            [webView loadRequest:homePageRequest];
        }
    }
}

- (void)restoreSavedScrollOffsetForTab:(BrowserTabViewModel *)tab webView:(BrowserWebView *)webView {
    if (tab == nil || !tab.needsScrollRestore || !tab.hasSavedScrollOffset) {
        return;
    }

    UIScrollView *scrollView = webView.scrollView;
    CGPoint savedScrollOffset = tab.savedScrollOffset;
    dispatch_async(dispatch_get_main_queue(), ^{
        [scrollView layoutIfNeeded];
        CGFloat maxOffsetX = MAX(0.0, scrollView.contentSize.width - CGRectGetWidth(scrollView.bounds));
        CGFloat maxOffsetY = MAX(0.0, scrollView.contentSize.height - CGRectGetHeight(scrollView.bounds));
        CGPoint clampedScrollOffset = CGPointMake(MIN(MAX(savedScrollOffset.x, 0.0), maxOffsetX),
                                                  MIN(MAX(savedScrollOffset.y, 0.0), maxOffsetY));
        [scrollView setContentOffset:clampedScrollOffset animated:NO];
        tab.savedScrollOffset = clampedScrollOffset;
        tab.hasSavedScrollOffset = YES;
        [self captureSnapshotForTab:tab];
        [self persistSession];
    });
    tab.needsScrollRestore = NO;
}

- (void)captureSnapshotForTab:(BrowserTabViewModel *)tab {
    if (tab == nil) {
        return;
    }

    if (!tab.needsScrollRestore) {
        [self updateStoredScrollOffsetForTab:tab];
    }

    BrowserWebView *webView = self.webViewsByTabIdentifier[tab.identifier];
    if (webView == nil || CGRectIsEmpty(webView.bounds)) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    [webView captureSnapshotWithCompletion:^(UIImage *snapshotImage) {
        dispatch_async(dispatch_get_main_queue(), ^{
            BrowserTabCoordinator *strongSelf = weakSelf;
            if (strongSelf == nil || snapshotImage == nil ||
                strongSelf.webViewsByTabIdentifier[tab.identifier] != webView) {
                return;
            }
            tab.snapshotImage = snapshotImage;
            [strongSelf.host browserTabCoordinatorSnapshotDidUpdateForTab:tab];
        });
    }];
}

- (void)captureSnapshotForCurrentTab {
    [self captureSnapshotForTab:self.activeTab];
}

- (void)prepareTabOverviewThumbnails {
    [self updateThumbnailStagingViewFrame];

    for (BrowserTabViewModel *tab in self.viewModel.tabs) {
        BrowserWebView *webView = self.webViewsByTabIdentifier[tab.identifier];
        if (tab == self.activeTab) {
            [self captureSnapshotForTab:tab];
            continue;
        }

        if (webView == nil) {
            webView = [self createConfiguredWebView];
            self.webViewsByTabIdentifier[tab.identifier] = webView;
        }

        [self parkWebViewForThumbnailing:webView];
        if (webView.request == nil) {
            [self loadStoredContentForTab:tab webView:webView fallbackToHomePage:NO];
            continue;
        }

        [self captureSnapshotForTab:tab];
    }
}

- (void)createNewTabLoadingHomePage:(BOOL)loadHomePage {
    if ([self.activeTab.URLString isEqualToString:kBrowserNewTabURL]) {
        [self showNewTabPageInWebView:self.activeWebView tab:self.activeTab];
        return;
    }
    BrowserTabViewModel *tab = [self.viewModel addStartPageTab];

    (void)loadHomePage;
    [self initWebView];
    [self refreshActiveTabUI];
    [self.rootView bringSubviewToFront:self.cursorView];

    [self showNewTabPageInWebView:self.activeWebView tab:tab];
    [self persistSession];
}

- (BOOL)createNewTabWithRequest:(NSURLRequest *)request {
    if (request == nil || request.URL == nil) {
        return NO;
    }

    if ([self.activeTab.URLString isEqualToString:kBrowserNewTabURL]) {
        [self.activeWebView loadRequest:request];
        [self persistSession];
        return YES;
    }

    [self captureSnapshotForTab:self.activeTab];
    [self.viewModel addTab];

    [self initWebView];
    [self refreshActiveTabUI];
    [self.rootView bringSubviewToFront:self.cursorView];
    [self.activeWebView loadRequest:request];
    [self persistSession];
    return YES;
}

- (void)reloadStartPageIfActive {
    if ([self.activeTab.URLString isEqualToString:kBrowserNewTabURL])
        [self showNewTabPageInWebView:self.activeWebView tab:self.activeTab];
}

- (void)switchToTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.viewModel.tabs.count) {
        return;
    }
    if (tabIndex == self.viewModel.activeTabIndex) {
        return;
    }

    BrowserTabViewModel *currentTab = self.activeTab;
    BOOL discardCurrentTab = [currentTab.URLString isEqualToString:kBrowserNewTabURL];
    if (!discardCurrentTab) [self captureSnapshotForTab:currentTab];

    [self.viewModel switchToTabAtIndex:tabIndex];
    if (discardCurrentTab) {
        NSInteger emptyTabIndex = [self.viewModel.tabs indexOfObjectIdenticalTo:currentTab];
        [self.webViewsByTabIdentifier[currentTab.identifier] removeFromSuperview];
        [self.webViewsByTabIdentifier removeObjectForKey:currentTab.identifier];
        if (emptyTabIndex != NSNotFound) [self.viewModel removeTabAtIndex:emptyTabIndex];
    }
    [self initWebView];
    [self.rootView bringSubviewToFront:self.cursorView];
    if ([self.activeTab.URLString isEqualToString:kBrowserNewTabURL]) {
        [self showNewTabPageInWebView:self.activeWebView tab:self.activeTab];
    } else if (self.activeWebView.request == nil) {
        [self loadStoredContentForTab:self.activeTab webView:self.activeWebView fallbackToHomePage:YES];
    }
    [self persistSession];
}

- (void)closeTabAtIndex:(NSInteger)tabIndex {
    if (tabIndex < 0 || tabIndex >= self.viewModel.tabs.count) {
        return;
    }

    BOOL closingActiveTab = tabIndex == self.viewModel.activeTabIndex;
    BrowserTabViewModel *tab = self.viewModel.tabs[tabIndex];
    [self.webViewsByTabIdentifier[tab.identifier] removeFromSuperview];
    [self.webViewsByTabIdentifier removeObjectForKey:tab.identifier];
    [self.viewModel removeTabAtIndex:tabIndex];

    if (self.viewModel.tabs.count == 0) {
        [self createNewTabLoadingHomePage:YES];
        return;
    }

    if (closingActiveTab) {
        [self initWebView];
        if (self.activeWebView.request == nil) {
            [self loadStoredContentForTab:self.activeTab webView:self.activeWebView fallbackToHomePage:YES];
        }
    }

    [self refreshActiveTabUI];
    [self persistSession];
}

- (void)recreateActiveWebViewPreservingCurrentURL {
    BrowserTabViewModel *tab = self.activeTab;
    if (tab == nil) {
        return;
    }

    NSString *currentURL = self.activeWebView.request.URL.absoluteString;
    [self.webViewsByTabIdentifier[tab.identifier] removeFromSuperview];
    [self.webViewsByTabIdentifier removeObjectForKey:tab.identifier];
    tab.requestURL = currentURL ?: @"";
    tab.previousURL = @"";
    tab.URLString = currentURL ?: @"";
    [self initWebView];

    if (currentURL.length > 0) {
        NSURLRequest *request = [self.navigationService requestForURLString:currentURL];
        if (request != nil) {
            [self.activeWebView loadRequest:request];
        }
    } else {
        [self loadHomePage];
    }
    [self persistSession];
}

- (void)setAdBlockEnabledForAllWebViews:(BOOL)enabled {
    for (BrowserWebView *webView in self.webViewsByTabIdentifier.allValues) {
        [webView setAdBlockEnabled:enabled];
    }
}

- (void)handleWebViewPanGesture:(UIPanGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state != UIGestureRecognizerStateEnded &&
        gestureRecognizer.state != UIGestureRecognizerStateCancelled &&
        gestureRecognizer.state != UIGestureRecognizerStateFailed) {
        return;
    }

    UIView *gestureView = gestureRecognizer.view;
    if (![gestureView isKindOfClass:[UIScrollView class]]) {
        return;
    }

    UIScrollView *scrollView = (UIScrollView *)gestureView;
    if (scrollView != self.activeWebView.scrollView) {
        return;
    }

    [self persistSession];
}

- (BOOL)isPrimaryDocumentRequest:(NSURLRequest *)request {
    NSURL *requestURL = request.URL;
    NSURL *mainDocumentURL = request.mainDocumentURL;
    if (requestURL == nil) {
        return NO;
    }
    if (mainDocumentURL == nil) {
        return YES;
    }
    return [requestURL isEqual:mainDocumentURL];
}

- (BrowserTabViewModel *)tabForWebView:(id)webView {
    for (BrowserTabViewModel *tab in self.viewModel.tabs) {
        if (self.webViewsByTabIdentifier[tab.identifier] == webView) {
            return tab;
        }
    }
    return nil;
}

- (void)prepareTabForRequest:(NSURLRequest *)request webView:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil || ![self isPrimaryDocumentRequest:request]) {
        return;
    }
    NSString *requestURL = request.URL.absoluteString ?: @"";
    if ([tab.URLString isEqualToString:kBrowserNewTabURL] &&
        [@[@"http", @"https"] containsObject:request.URL.scheme.lowercaseString]) {
        tab.URLString = requestURL;
    }
    if (tab.URLString.length > 0 && ![tab.URLString isEqualToString:requestURL]) {
        tab.savedScrollOffset = CGPointZero;
        tab.hasSavedScrollOffset = NO;
        tab.needsScrollRestore = NO;
    }
    tab.requestURL = requestURL;
}

- (void)webViewDidStartLoad:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }

    if (tab == self.activeTab && ![tab.previousURL isEqualToString:tab.requestURL]) {
        [self.topMenuView.loadingSpinner startAnimating];
    }
    tab.previousURL = tab.requestURL;
}

- (void)webViewDidFinishLoad:(id)webView {
    BrowserTabViewModel *tab = [self tabForWebView:webView];
    if (tab == nil) {
        return;
    }

    if (tab == self.activeTab) {
        [self.topMenuView.loadingSpinner stopAnimating];
    }

    NSString *theTitle = [webView title];
    NSURLRequest *request = [webView request];
    NSString *currentURL = request.URL.absoluteString ?: @"";
    if ([currentURL isEqualToString:kBrowserNewTabURL] ||
        (currentURL.length == 0 && [tab.URLString isEqualToString:kBrowserNewTabURL])) {
        tab.title = @"New Tab";
        tab.URLString = kBrowserNewTabURL;
        tab.requestURL = kBrowserNewTabURL;
        if (tab == self.activeTab && self.pendingNewTabSelectionGroup.length > 0) {
            NSString *group = self.pendingNewTabSelectionGroup;
            NSUInteger index = self.pendingNewTabSelectionIndex;
            self.pendingNewTabSelectionGroup = nil;
            NSString *script = [NSString stringWithFormat:@"window.browserNewTabSelect && window.browserNewTabSelect('%@', %lu)",
                                group, (unsigned long)index];
            [webView evaluateJavaScript:script completion:^(__unused NSString *result) {}];
        }
    } else {
        [self.navigationService updateTab:tab withPageTitle:theTitle currentURLString:currentURL];
    }

    if (tab == self.activeTab) {
        [self refreshActiveTabUI];
    } else if ([self isWebViewStaged:webView]) {
        [webView pauseAllMediaPlayback];
    }
    [self restoreSavedScrollOffsetForTab:tab webView:webView];
    if (!tab.needsScrollRestore) {
        [self captureSnapshotForTab:tab];
        [self persistSession];
    }
}

@end
