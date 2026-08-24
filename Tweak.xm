#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ----- Reachability classes (declared) -----
@interface SBReachabilityManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isReachabilityActive;
- (void)activateReachability;
- (void)deactivateReachability;
@end

@interface SBReachabilityController : NSObject
+ (instancetype)sharedInstance;
- (void)activateReachability:(BOOL)active;
@end

// ----- HomeGrabber class -----
@interface SBHomeGrabberView : UIView
@end

// ----- Category to add gesture handling -----
@interface SBHomeGrabberView (DoubleTap)
- (void)dd_addDoubleTapGesture;
- (void)dd_handleDoubleTap:(UITapGestureRecognizer *)gesture;
- (void)dd_toggleReachability;
@end

@implementation SBHomeGrabberView (DoubleTap)

- (void)dd_addDoubleTapGesture {
    // Remove existing double-tap gestures to avoid duplicates
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 2) {
                [self removeGestureRecognizer:gr];
            }
        }
    }
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dd_handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:doubleTap];
    NSLog(@"DoubleTapReachability: Gesture added to home bar");
}

- (void)dd_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    [self dd_toggleReachability];
}

- (void)dd_toggleReachability {
    // Try multiple Reachability classes
    Class managerClass = NSClassFromString(@"SBReachabilityManager");
    if (!managerClass) managerClass = NSClassFromString(@"SBReachabilityController");
    
    if (managerClass) {
        id manager = [managerClass performSelector:@selector(sharedInstance)];
        // Use respondsToSelector for safety
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
        } else if ([manager respondsToSelector:@selector(toggleReachability)]) {
            [manager performSelector:@selector(toggleReachability)];
        } else if ([manager respondsToSelector:@selector(activateReachability:)]) {
            [manager performSelector:@selector(activateReachability:) withObject:@(YES)];
        }
    } else {
        // Fallback: post a Darwin notification
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             CFSTR("com.apple.reachability.toggle"),
                                             NULL, NULL, YES);
    }
}

@end

// ----- Hook SBHomeGrabberView's didMoveToWindow -----
%hook SBHomeGrabberView

- (void)didMoveToWindow {
    %orig;
    if (self.window) {
        [self dd_addDoubleTapGesture];
    }
}

%end
