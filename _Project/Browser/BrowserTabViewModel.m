#import "BrowserTabViewModel.h"

@implementation BrowserTabViewModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [[[NSUUID UUID] UUIDString] copy];
        _requestURL = @"";
        _previousURL = @"";
        _title = @"New Tab";
        _URLString = @"";
        _savedScrollOffset = CGPointZero;
        _hasSavedScrollOffset = NO;
        _needsScrollRestore = NO;
        _navigationURLs = @[];
        _navigationIndex = NSNotFound;
        _pendingNavigationIndex = NSNotFound;
    }
    return self;
}

- (instancetype)initWithSessionRepresentation:(NSDictionary *)sessionRepresentation {
    self = [self init];
    if (self == nil) {
        return nil;
    }
    NSString *identifier = sessionRepresentation[@"identifier"];
    if ([identifier isKindOfClass:NSString.class] && identifier.length > 0) _identifier = [identifier copy];
    
    NSString *requestURL = [sessionRepresentation[@"requestURL"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"requestURL"] : @"";
    NSString *previousURL = [sessionRepresentation[@"previousURL"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"previousURL"] : @"";
    NSString *title = [sessionRepresentation[@"title"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"title"] : @"New Tab";
    NSString *URLString = [sessionRepresentation[@"URLString"] isKindOfClass:[NSString class]] ? sessionRepresentation[@"URLString"] : @"";
    NSNumber *scrollOffsetX = [sessionRepresentation[@"scrollOffsetX"] isKindOfClass:[NSNumber class]] ? sessionRepresentation[@"scrollOffsetX"] : nil;
    NSNumber *scrollOffsetY = [sessionRepresentation[@"scrollOffsetY"] isKindOfClass:[NSNumber class]] ? sessionRepresentation[@"scrollOffsetY"] : nil;
    
    self.requestURL = requestURL;
    self.previousURL = previousURL;
    self.title = title.length > 0 ? title : @"New Tab";
    self.URLString = URLString;
    NSArray *savedURLs = [sessionRepresentation[@"navigationURLs"] isKindOfClass:NSArray.class]
        ? sessionRepresentation[@"navigationURLs"] : @[];
    NSMutableArray<NSString *> *validURLs = [NSMutableArray array];
    for (id candidate in savedURLs) {
        if (![candidate isKindOfClass:NSString.class]) continue;
        NSURL *URL = [NSURL URLWithString:candidate];
        if (URL.host.length > 0 && [@[@"http", @"https"] containsObject:URL.scheme.lowercaseString])
            [validURLs addObject:candidate];
    }
    self.navigationURLs = validURLs;
    NSInteger savedIndex = [sessionRepresentation[@"navigationIndex"] respondsToSelector:@selector(integerValue)]
        ? [sessionRepresentation[@"navigationIndex"] integerValue] : (NSInteger)validURLs.count - 1;
    self.navigationIndex = validURLs.count > 0 ? MIN(MAX(savedIndex, 0), (NSInteger)validURLs.count - 1) : NSNotFound;
    self.navigationHistoryRestored = validURLs.count > 0;
    if (validURLs.count == 0 && URLString.length > 0) [self recordNavigationURLString:URLString];
    if (scrollOffsetX != nil && scrollOffsetY != nil) {
        self.savedScrollOffset = CGPointMake(scrollOffsetX.doubleValue, scrollOffsetY.doubleValue);
        self.hasSavedScrollOffset = YES;
        self.needsScrollRestore = YES;
    }
    
    return self;
}

- (NSDictionary *)sessionRepresentation {
    NSMutableDictionary *representation = [NSMutableDictionary dictionary];
    representation[@"identifier"] = self.identifier;
    representation[@"requestURL"] = self.requestURL ?: @"";
    representation[@"previousURL"] = self.previousURL ?: @"";
    representation[@"title"] = self.title ?: @"New Tab";
    representation[@"URLString"] = self.URLString ?: @"";
    representation[@"navigationURLs"] = self.navigationURLs ?: @[];
    representation[@"navigationIndex"] = @(self.navigationIndex);
    if (self.hasSavedScrollOffset) {
        representation[@"scrollOffsetX"] = @(self.savedScrollOffset.x);
        representation[@"scrollOffsetY"] = @(self.savedScrollOffset.y);
    }
    return representation;
}

- (void)recordNavigationURLString:(NSString *)URLString {
    NSURL *URL = [NSURL URLWithString:URLString];
    if (URL.host.length == 0 || ![@[@"http", @"https"] containsObject:URL.scheme.lowercaseString]) {
        self.pendingNavigationIndex = NSNotFound;
        return;
    }
    NSMutableArray<NSString *> *URLs = [self.navigationURLs mutableCopy];
    if (self.pendingNavigationIndex != NSNotFound && self.pendingNavigationIndex >= 0 &&
        self.pendingNavigationIndex < URLs.count) {
        self.navigationIndex = self.pendingNavigationIndex;
        URLs[self.navigationIndex] = URLString;
    } else if (self.navigationIndex >= 0 && self.navigationIndex < URLs.count &&
               [URLs[self.navigationIndex] isEqualToString:URLString]) {
        // A reload or session restoration does not add a navigation step.
    } else {
        if (self.navigationIndex != NSNotFound && self.navigationIndex + 1 < URLs.count) {
            [URLs removeObjectsInRange:NSMakeRange(self.navigationIndex + 1, URLs.count - self.navigationIndex - 1)];
        }
        [URLs addObject:URLString];
        self.navigationIndex = URLs.count - 1;
    }
    self.navigationURLs = URLs;
    self.pendingNavigationIndex = NSNotFound;
}

@end
