#import <UIKit/UIKit.h>

@interface FloatingLogView : UIWindow
+ (instancetype)sharedInstance;
- (void)log:(NSString *)fmt, ... NS_FORMAT_FUNCTION(1,2);
@end
