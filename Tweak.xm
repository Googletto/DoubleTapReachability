#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

%hook SBHomeGrabberView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    
    static NSTimeInterval lastTapTime = 0;
    static NSInteger tapCount = 0;
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    if (currentTime - lastTapTime < 0.5) {
        tapCount++;
        
        if (tapCount >= 2) {
            // Toggle Reachability
            SBReachabilityManager *manager = [%c(SBReachabilityManager) sharedInstance];
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
