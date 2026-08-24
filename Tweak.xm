#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// Declare the Reachability Manager interface
@interface SBReachabilityManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isReachabilityActive;
- (void)activateReachability;
- (void)deactivateReachability;
@end

// Declare HomeGrabberView (to avoid forward declaration warning)
@interface SBHomeGrabberView : UIView
@end

%hook SBHomeGrabberView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    
    static NSTimeInterval lastTapTime = 0;
    static NSInteger tapCount = 0;
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    if (currentTime - lastTapTime < 0.5) {
        tapCount++;
        
        if (tapCount >= 2) {
            // Get the Reachability manager via runtime class
            Class managerClass = %c(SBReachabilityManager);
            id manager = [managerClass sharedInstance];
            
            if ([manager isReachabilityActive]) {
                [manager deactivateReachability];
            } else {
                [manager activateReachability];
            }
            
            tapCount = 0;
            lastTapTime = 0;
            
            // Haptic feedback
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
            [generator impactOccurred];
        }
    } else {
        tapCount = 1;
    }
    
    lastTapTime = currentTime;
}

%end
