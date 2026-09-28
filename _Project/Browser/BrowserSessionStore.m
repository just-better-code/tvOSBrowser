#import "BrowserSessionStore.h"

#import "BrowserNavigationService.h"
#import "BrowserTabViewModel.h"
#import "BrowserViewModel.h"

static NSString * const kBrowserSessionDefaultsKey = @"BrowserSession";
static NSString * const kBrowserSessionTabsKey = @"tabs";
static NSString * const kBrowserSessionActiveTabIndexKey = @"activeTabIndex";
static NSString * const kBrowserSessionVersionKey = @"version";
static NSString * const kBrowserSavedURLToReopenDefaultsKey = @"savedURLtoReopen";
static NSNumber *BrowserSessionVersion(void) {
    return @1;
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
    if (viewModel.tabs.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBrowserSessionDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }
    
    NSMutableArray *tabRepresentations = [NSMutableArray arrayWithCapacity:viewModel.tabs.count];
    NSInteger savedActiveIndex = NSNotFound;
    for (BrowserTabViewModel *tab in viewModel.tabs) {
        if ([tab.URLString isEqualToString:@"about:blank"]) continue;
        if (tab == viewModel.activeTab) savedActiveIndex = tabRepresentations.count;
        [tabRepresentations addObject:[tab sessionRepresentation]];
    }
    if (tabRepresentations.count == 0) {
        [[NSUserDefaults standardUserDefaults] removeObjectForKey:kBrowserSessionDefaultsKey];
        [[NSUserDefaults standardUserDefaults] synchronize];
        return;
    }
    
    NSDictionary *sessionRepresentation = @{
        kBrowserSessionVersionKey: BrowserSessionVersion(),
        kBrowserSessionActiveTabIndexKey: @(savedActiveIndex == NSNotFound ? tabRepresentations.count - 1 : savedActiveIndex),
        kBrowserSessionTabsKey: tabRepresentations
    };

    [[NSUserDefaults standardUserDefaults] setObject:sessionRepresentation forKey:kBrowserSessionDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (NSDictionary *)restoredSessionRepresentation {
    NSDictionary *defaultsRepresentation = [[NSUserDefaults standardUserDefaults] objectForKey:kBrowserSessionDefaultsKey];
    if ([defaultsRepresentation isKindOfClass:[NSDictionary class]]) {
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
