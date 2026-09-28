#import <Foundation/Foundation.h>

@interface BrowserHistoryStore : NSObject

+ (instancetype)sharedStore;
- (void)recordURLString:(NSString *)URLString title:(NSString *)title;
- (NSArray<NSDictionary *> *)mostVisitedWithLimit:(NSUInteger)limit;
- (NSArray<NSDictionary *> *)allVisits;
- (void)deleteVisitsWithIdentifiers:(NSArray<NSNumber *> *)identifiers;
- (void)deleteAllVisits;
- (void)deleteVisitsForURLString:(NSString *)URLString;
- (NSArray<NSArray<NSString *> *> *)favorites;
- (void)saveFavorites:(NSArray<NSArray<NSString *> *> *)favorites;

@end
