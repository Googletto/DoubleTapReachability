#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

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
- (void)toggleReachability;
@end

// ----- Hook the home screen view controller to add gesture -----
%hook SBHomeScreenViewController   // or SBDashBoardViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [self performSelector:@selector(addDoubleTapToHomeBar) withObject:nil afterDelay:1.0];
    });
}

- (void)addDoubleTapToHomeBar {
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) {
        NSLog(@"DoubleTapReachability: No keyWindow, retrying...");
        [self performSelector:@selector(addDoubleTapToHomeBar) withObject:nil afterDelay:2.0];
        return;
    }

    // Search for SBHomeGrabberView
    __block UIView *homeBar = nil;
    [self findHomeGrabberInView:keyWindow result:&homeBar];
    
    if (homeBar) {
        [self attachGestureToView:homeBar];
    } else {
        NSLog(@"DoubleTapReachability: Home bar not found, retrying...");
        [self performSelector:@selector(addDoubleTapToHomeBar) withObject:nil afterDelay:3.0];
    }
}

- (void)findHomeGrabberInView:(UIView *)view result:(UIView **)outView {
    if (*outView) return;
    // Check class names: SBHomeGrabberView or _SBHomeGrabberView
    if ([view isKindOfClass:NSClassFromString(@"SBHomeGrabberView")] ||
        [view isKindOfClass:NSClassFromString(@"_SBHomeGrabberView")]) {
        *outView = view;
        return;
    }
    for (UIView *subview in view.subviews) {
        [self findHomeGrabberInView:subview result:outView];
        if (*outView) return;
    }
}

- (void)attachGestureToView:(UIView *)view {
    // Remove existing double-tap gestures
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 2) {
                [view removeGestureRecognizer:gr];
            }
        }
    }

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    [view addGestureRecognizer:doubleTap];
    NSLog(@"DoubleTapReachability: Gesture attached to home bar!");
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    NSLog(@"DoubleTapReachability: Double-tap detected!");

    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];

    // Toggle Reachability
    [self toggleReachability];
}

- (void)toggleReachability {
    NSLog(@"DoubleTapReachability: Toggling Reachability...");
    
    // Try multiple known managers
    NSArray *classNames = @[@"SBReachabilityManager", @"SBReachabilityController"];
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id manager = [cls performSelector:@selector(sharedInstance)];
        if (!manager) continue;

        // Prefer toggleReachability
        if ([manager respondsToSelector:@selector(toggleReachability)]) {
            [manager performSelector:@selector(toggleReachability)];
            NSLog(@"DoubleTapReachability: Used toggleReachability on %@", className);
            return;
        }

        // Try activateReachability: with BOOL
        if ([manager respondsToSelector:@selector(activateReachability:)]) {
            BOOL active = NO;
            if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
                active = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            }
            if (active) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                } else {
                    [manager performSelector:@selector(activateReachability:) withObject:@(NO)];
                }
            } else {
                [manager performSelector:@selector(activateReachability:) withObject:@(YES)];
            }
            NSLog(@"DoubleTapReachability: Used activateReachability: on %@", className);
            return;
        }

        // Fallback: activate/deactivate separate
        if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
            BOOL active = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            if (active) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                    NSLog(@"DoubleTapReachability: Used deactivateReachability on %@", className);
                    return;
                }
            } else {
                if ([manager respondsToSelector:@selector(activateReachability)]) {
                    [manager performSelector:@selector(activateReachability)];
                    NSLog(@"DoubleTapReachability: Used activateReachability on %@", className);
                    return;
                }
            }
        }
    }

    // Final fallback: Darwin notification
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.apple.reachability.toggle"),
                                         NULL, NULL, YES);
    NSLog(@"DoubleTapReachability: Used Darwin notification fallback");
}

%end
