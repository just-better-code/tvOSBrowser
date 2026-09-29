#import "BrowserNavigationService.h"

#import "BrowserPreferencesStore.h"
#import "BrowserTabViewModel.h"
#import "BrowserHistoryStore.h"


@interface BrowserNavigationService ()

@property (nonatomic) BrowserPreferencesStore *preferencesStore;

@end

@implementation BrowserNavigationService

- (instancetype)init {
    return [self initWithPreferencesStore:[BrowserPreferencesStore new]];
}

- (instancetype)initWithPreferencesStore:(BrowserPreferencesStore *)preferencesStore {
    self = [super init];
    if (self) {
        _preferencesStore = preferencesStore ?: [BrowserPreferencesStore new];
        [_preferencesStore ensureUserAgentConsistency];
    }
    return self;
}

- (NSURLRequest *)homePageRequest {
    NSString *homePageURLString = self.preferencesStore.homePageURLString;
    if (homePageURLString.length == 0) {
        homePageURLString = @"http://www.google.com";
    }
    return [self requestForURLString:homePageURLString];
}

- (NSURLRequest *)requestForEnteredAddressString:(NSString *)addressString {
    NSString *trimmedAddress = [self trimmedString:addressString];
    if (trimmedAddress.length == 0) {
        return nil;
    }
    
    if (![trimmedAddress hasPrefix:@"http://"] && ![trimmedAddress hasPrefix:@"https://"]) {
        trimmedAddress = [@"http://" stringByAppendingString:trimmedAddress];
    }
    return [self requestForURLString:trimmedAddress];
}

- (NSURLRequest *)googleSearchRequestForQuery:(NSString *)query {
    NSString *sanitizedQuery = [self sanitizedSearchQuery:query];
    if (sanitizedQuery.length == 0) {
        return nil;
    }
    
    NSString *searchURLString = [NSString stringWithFormat:@"https://www.google.com/search?q=%@", sanitizedQuery];
    return [self requestForURLString:searchURLString];
}

- (NSURLRequest *)googleSearchRequestForFailedRequestURLString:(NSString *)requestURLString {
    NSString *searchQuery = [self trimmedString:requestURLString];
    if (searchQuery.length == 0) {
        return nil;
    }
    
    if ([searchQuery hasSuffix:@"/"]) {
        searchQuery = [searchQuery substringToIndex:searchQuery.length - 1];
    }
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"http://" withString:@""];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"https://" withString:@""];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"www." withString:@""];
    
    return [self googleSearchRequestForQuery:searchQuery];
}

- (void)updateTab:(BrowserTabViewModel *)tab
    withPageTitle:(NSString *)pageTitle
  currentURLString:(NSString *)currentURLString {
    if (tab == nil) {
        return;
    }
    
    NSString *safeTitle = pageTitle ?: @"";
    NSString *safeURLString = currentURLString ?: @"";
    tab.title = safeTitle.length > 0 ? safeTitle : @"New Tab";
    tab.URLString = safeURLString;
    
    [self persistHistoryItemWithURLString:safeURLString title:safeTitle];
}

- (BOOL)shouldIgnoreLoadError:(NSError *)error {
    NSInteger errorCode = error.code;
    return errorCode == NSURLErrorCancelled || errorCode == 204;
}

- (NSURLRequest *)requestForURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL == nil) {
        return nil;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:URL];
    NSString *userAgent = self.preferencesStore.userAgent;
    if (userAgent.length > 0) {
        [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
    }
    return request;
}

- (NSString *)trimmedString:(NSString *)string {
    if (string == nil) {
        return @"";
    }
    return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSString *)sanitizedSearchQuery:(NSString *)query {
    NSString *trimmedQuery = [self trimmedString:query];
    if (trimmedQuery.length == 0) {
        return @"";
    }
    
    NSString *searchQuery = [trimmedQuery stringByReplacingOccurrencesOfString:@" " withString:@"+"];
    searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"." withString:@"+"];
    while ([searchQuery containsString:@"++"]) {
        searchQuery = [searchQuery stringByReplacingOccurrencesOfString:@"++" withString:@"+"];
    }
    
    return [searchQuery stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];
}

- (void)persistHistoryItemWithURLString:(NSString *)URLString title:(NSString *)title {
    [[BrowserHistoryStore sharedStore] recordURLString:URLString title:title];
}

@end
