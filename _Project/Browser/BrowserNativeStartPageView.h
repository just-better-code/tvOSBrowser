#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface BrowserNativeStartPageView : UIView

@property (nonatomic, copy, nullable) void (^openURLString)(NSString *URLString);
@property (nonatomic, copy, nullable) void (^openSearch)(void);
@property (nonatomic, copy, nullable) void (^showAllHistory)(void);
@property (nonatomic, copy, nullable) void (^manageFavorite)(NSUInteger index);
@property (nonatomic, copy, nullable) void (^deleteRecentVisit)(NSString *URLString);

- (void)reloadFavorites:(NSArray<NSArray<NSString *> *> *)favorites
                recents:(NSArray<NSDictionary *> *)recents
         selectingGroup:(nullable NSString *)group
                  index:(NSUInteger)index;
- (void)navigateInDirection:(NSString *)direction;
- (void)activateSelection;
- (void)activateAtPoint:(CGPoint)point;
- (void)showOptionForSelection;
- (void)showOptionAtPoint:(CGPoint)point;

@end

NS_ASSUME_NONNULL_END
