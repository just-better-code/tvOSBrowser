#import "BrowserSessionStore.h"

#import "BrowserNavigationService.h"
#import "BrowserHistoryStore.h"
#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static NSString * const kBrowserSessionDefaultsKey = @"BrowserSession";
static NSString * const kBrowserSessionTabsKey = @"tabs";
static NSString * const kBrowserSessionActiveTabIndexKey = @"activeTabIndex";
static NSString * const kBrowserSessionVersionKey = @"version";
static NSString * const kBrowserSavedURLToReopenDefaultsKey = @"savedURLtoReopen";
static NSString * const kBrowserSessionSQLiteSavePendingKey = @"BrowserSessionSQLiteSavePending";
static NSNumber *BrowserSessionVersion(void) {
    return @2;
}

@implementation BrowserSessionStore

- (BOOL)restoreSessionIntoViewModel:(BrowserViewModel *)viewModel {
    NSDictionary *sessionRepresentation = [self restoredSessionRepresentation];
    if (![sessionRepresentation isKindOfClass:[NSDictionary class]]) {
        return NO;
    }
    
    NSArray *tabRepresentations = [sessionRepresentation[kBrowserSessionTabsKey] isKindOfClass:[NSArray class]] ? sessionRepresentation[kBrowserSessionTabsKey] : nil;
    if (tabRepresentations.count == 0) {
        return NO;
    }
    
    NSInteger activeTabIndex = [sessionRepresentation[kBrowserSessionActiveTabIndexKey] respondsToSelector:@selector(integerValue)] ? [sessionRepresentation[kBrowserSessionActiveTabIndexKey] integerValue] : 0;
    NSInteger restoredActiveIndex = NSNotFound;
    NSMutableArray<BrowserTabViewModel *> *tabs = [NSMutableArray array];
    for (NSUInteger originalIndex = 0; originalIndex < tabRepresentations.count; originalIndex++) {
        NSDictionary *tabRepresentation = tabRepresentations[originalIndex];
        if (![tabRepresentation isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        BrowserTabViewModel *tab = [[BrowserTabViewModel alloc] initWithSessionRepresentation:tabRepresentation];
        if (tab != nil && ![tab.URLString isEqualToString:@"about:blank"]) {
            if (originalIndex == activeTabIndex) restoredActiveIndex = tabs.count;
            [tabs addObject:tab];
        }
    }
    
    if (tabs.count == 0) {
        return NO;
    }
    
    [viewModel restoreTabs:tabs activeTabIndex:restoredActiveIndex == NSNotFound ? tabs.count - 1 : restoredActiveIndex];
    return YES;
}

- (void)saveSessionForViewModel:(BrowserViewModel *)viewModel {
    NSMutableArray *tabRepresentations = [NSMutableArray arrayWithCapacity:viewModel.tabs.count];
    NSInteger savedActiveIndex = NSNotFound;
    for (BrowserTabViewModel *tab in viewModel.tabs) {
        if ([tab.URLString isEqualToString:@"about:blank"]) continue;
        if (tab == viewModel.activeTab) savedActiveIndex = tabRepresentations.count;
        [tabRepresentations addObject:[tab sessionRepresentation]];
    }
    NSDictionary *sessionRepresentation = @{
        kBrowserSessionVersionKey: BrowserSessionVersion(),
        kBrowserSessionActiveTabIndexKey: @(savedActiveIndex == NSNotFound ? MAX((NSInteger)tabRepresentations.count - 1, 0) : savedActiveIndex),
        kBrowserSessionTabsKey: tabRepresentations
    };

    BOOL saved = [[BrowserHistoryStore sharedStore] saveBrowserSession:sessionRepresentation];
    [[NSUserDefaults standardUserDefaults] setBool:!saved forKey:kBrowserSessionSQLiteSavePendingKey];
    if (!saved) {
        NSLog(@"[Session] SQLite save failed; keeping the session in the preferences backup");
    }
    // tvOS may purge caches. Keep a recoverable backup of the complete session.
    [[NSUserDefaults standardUserDefaults] setObject:sessionRepresentation forKey:kBrowserSessionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDictionary *)restoredSessionRepresentation {
    NSDictionary *storedSession = [[BrowserHistoryStore sharedStore] savedBrowserSession];
    if (storedSession != nil && ![[NSUserDefaults standardUserDefaults] boolForKey:kBrowserSessionSQLiteSavePendingKey]) return storedSession;
    NSDictionary *defaultsRepresentation = [[NSUserDefaults standardUserDefaults] objectForKey:kBrowserSessionDefaultsKey];
    if ([defaultsRepresentation isKindOfClass:[NSDictionary class]]) {
        BOOL saved = [[BrowserHistoryStore sharedStore] saveBrowserSession:defaultsRepresentation];
        [[NSUserDefaults standardUserDefaults] setBool:!saved forKey:kBrowserSessionSQLiteSavePendingKey];
        return defaultsRepresentation;
    }

    return nil;
}

- (NSURLRequest *)consumeSavedURLToReopenRequestWithNavigationService:(BrowserNavigationService *)navigationService {
    NSString *savedURLString = [[NSUserDefaults standardUserDefaults] stringForKey:kBrowserSavedURLToReopenDefaultsKey];
    if (savedURLString.length == 0) {
        return nil;
    }

    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBrowserSavedURLToReopenDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if (navigationService == nil) {
        return nil;
    }
    return [navigationService requestForURLString:savedURLString];
}

@end
