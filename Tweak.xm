#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <SpringBoard/SpringBoard.h>

// ----- Declare SBHomeGrabberView -----
@interface SBHomeGrabberView : UIView
@property (nonatomic, readonly) UIWindow *window;
@property (nonatomic, readonly) NSArray<UIGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
@end

// ----- Reachability classes -----
@interface SBReachabilityManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isReachabilityActive;
- (void)activateReachability;
- (void)deactivateReachability;
@end

@interface SBReachabilityController : NSObject
+ (instancetype)sharedInstance;
- (void)activateReachability:(BOOL)active;
- (void)toggleReachability;
@end

// ----- Hook SBHomeGrabberView -----
%hook SBHomeGrabberView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    // Remove any existing double-tap gestures (cleanup)
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 2) {
                [self removeGestureRecognizer:gr];
                NSLog(@"DoubleTapReachability: Removed existing double-tap gesture");
            }
        }
    }

    // Add fresh double-tap gesture
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dd_handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.delaysTouchesEnded = NO;  // Allow immediate action
    [self addGestureRecognizer:doubleTap];
    NSLog(@"DoubleTapReachability: Added double-tap gesture to home bar");
}

- (void)dd_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    NSLog(@"DoubleTapReachability: Double-tap detected!");

    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];

    // Toggle Reachability — try everything
    [self dd_toggleReachability];
}

- (void)dd_toggleReachability {
    NSLog(@"DoubleTapReachability: Attempting to toggle Reachability");

    // Try known Reachability managers
    NSArray *classNames = @[@"SBReachabilityManager", @"SBReachabilityController"];
    for (NSString *className in classNames) {
        Class managerClass = NSClassFromString(className);
        if (!managerClass) continue;

        id manager = [managerClass performSelector:@selector(sharedInstance)];
        if (!manager) continue;

        // Method 1: toggleReachability (if available)
        if ([manager respondsToSelector:@selector(toggleReachability)]) {
            [manager performSelector:@selector(toggleReachability)];
            NSLog(@"DoubleTapReachability: Used toggleReachability on %@", className);
            return;
        }

        // Method 2: activateReachability: with BOOL (force on/off)
        if ([manager respondsToSelector:@selector(activateReachability:)]) {
            // Try to detect current state, but fallback to toggling
            BOOL isActive = NO;
            if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
                isActive = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            }
            // Toggle: if active -> deactivate, else activate
            if (isActive) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                } else {
                    // Force activate with NO
                    [manager performSelector:@selector(activateReachability:) withObject:@(NO)];
                }
            } else {
                [manager performSelector:@selector(activateReachability:) withObject:@(YES)];
            }
            NSLog(@"DoubleTapReachability: Used activateReachability: on %@", className);
            return;
        }

        // Method 3: activate / deactivate separately
        if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
            BOOL active = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            if (active) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                    NSLog(@"DoubleTapReachability: Used deactivateReachability on %@", className);
                }
            } else {
                if ([manager respondsToSelector:@selector(activateReachability)]) {
                    [manager performSelector:@selector(activateReachability)];
                    NSLog(@"DoubleTapReachability: Used activateReachability on %@", className);
                }
            }
            return;
        }
    }

    // Fallback: Post a Darwin notification (some tweaks respond to this)
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.apple.reachability.toggle"),
                                         NULL, NULL, YES);
    NSLog(@"DoubleTapReachability: Used Darwin notification fallback");
}

%end
