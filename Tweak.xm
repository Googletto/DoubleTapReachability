#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <SpringBoard/SpringBoard.h>

// ----- Forward declarations -----
@interface SBReachabilityManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isReachabilityActive;
- (void)activateReachability;
- (void)deactivateReachability;
@end

@interface SBReachabilityController : NSObject   // fallback class
+ (instancetype)sharedInstance;
- (void)activateReachability:(BOOL)active;
@end

@interface SBHomeGrabberView : UIView
@end

// ----- Hook into SpringBoard to add gesture -----
%hook SBHomeScreenViewController   // or SBDashBoardViewController

- (void)viewDidLoad {
    %orig;
    
    // Wait a bit for the home bar to be created
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self addDoubleTapGestureToHomeBar];
    });
}

- (void)addDoubleTapGestureToHomeBar {
    // Find the home bar view in the view hierarchy
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    
    // Search for SBHomeGrabberView
    __block SBHomeGrabberView *homeBar = nil;
    [self findHomeGrabberInView:keyWindow result:&homeBar];
    
    if (homeBar) {
        // Remove any existing double-tap gesture (just in case)
        for (UIGestureRecognizer *gr in homeBar.gestureRecognizers) {
            if ([gr isKindOfClass:[UITapGestureRecognizer class]] && [(UITapGestureRecognizer *)gr numberOfTapsRequired] == 2) {
                [homeBar removeGestureRecognizer:gr];
            }
        }
        
        // Add new double-tap gesture
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.numberOfTouchesRequired = 1;
        [homeBar addGestureRecognizer:doubleTap];
        
        NSLog(@"DoubleTapReachability: Added double-tap gesture to home bar!");
    } else {
        NSLog(@"DoubleTapReachability: Failed to find home bar, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [self addDoubleTapGestureToHomeBar];
        });
    }
}

- (void)findHomeGrabberInView:(UIView *)view result:(SBHomeGrabberView **)outView {
    if (*outView) return;
    if ([view isKindOfClass:NSClassFromString(@"SBHomeGrabberView")]) {
        *outView = (SBHomeGrabberView *)view;
        return;
    }
    for (UIView *subview in view.subviews) {
        [self findHomeGrabberInView:subview result:outView];
        if (*outView) return;
    }
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    
    // Toggle Reachability
    [self toggleReachability];
}

- (void)toggleReachability {
    // Try multiple possible class names
    Class managerClass = NSClassFromString(@"SBReachabilityManager");
    if (!managerClass) managerClass = NSClassFromString(@"SBReachabilityController");
    
    if (managerClass) {
        id manager = [managerClass performSelector:@selector(sharedInstance)];
        if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
            BOOL active = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            if (active) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                }
            } else {
                if ([manager respondsToSelector:@selector(activateReachability)]) {
                    [manager performSelector:@selector(activateReachability)];
                }
            }
        } else {
            // Fallback: try toggle method
            if ([manager respondsToSelector:@selector(toggleReachability)]) {
                [manager performSelector:@selector(toggleReachability)];
            } else if ([manager respondsToSelector:@selector(activateReachability:)]) {
                // Some versions use a parameter
                [manager performSelector:@selector(activateReachability:) withObject:@(YES)];
            }
        }
    } else {
        // Fallback: post a notification (some tweaks use this)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.apple.reachability.toggle"),
                                             NULL, NULL, YES);
    }
}

%end
