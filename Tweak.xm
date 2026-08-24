#import <UIKit/UIKit.h>
#import <SpringBoard/SpringBoard.h>

// Hook into the home bar (gesture recognizer)
%hook SBHomeGrabberView

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    %orig;
    
    static NSTimeInterval lastTapTime = 0;
    static NSInteger tapCount = 0;
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    
    // Double tap detection (within 0.5 seconds)
    if (currentTime - lastTapTime < 0.5) {
        tapCount++;
        
        if (tapCount >= 2) {
            // Trigger Reachability
            [self triggerReachability];
            
            // Reset counter
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

- (void)triggerReachability {
    // Get the SpringBoard instance
    SBReachabilityManager *manager = [%c(SBReachabilityManager) sharedInstance];
    
    // Toggle reachability (if already active, deactivate it)
    if ([manager isReachabilityActive]) {
        [manager deactivateReachability];
    } else {
        [manager activateReachability];
    }
}

%end

// Optional: Add settings toggle (using Preferences)
%hook SBHomeScreenViewController

- (void)viewDidLoad {
    %orig;
    
    // Load preference: is tweak enabled?
    BOOL tweakEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"DoubleTapReachabilityEnabled"];
    if (!tweakEnabled) {
        // Default to enabled
        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DoubleTapReachabilityEnabled"];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

%end
