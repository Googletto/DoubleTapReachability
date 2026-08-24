#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ----- Declare SBHomeGrabberView as a subclass of UIView -----
@interface SBHomeGrabberView : UIView
@property (nonatomic, readonly) UIWindow *window;
@property (nonatomic, readonly) NSArray<UIGestureRecognizer *> *gestureRecognizers;
- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
- (void)removeGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer;
@end

// ----- Reachability classes (runtime lookup) -----
@interface SBReachabilityManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isReachabilityActive;
- (void)activateReachability;
- (void)deactivateReachability;
@end

// ----- Hook SBHomeGrabberView -----
%hook SBHomeGrabberView

- (void)didMoveToWindow {
    %orig;
    if (!self.window) return;

    // Use associated object to avoid adding gesture twice
    static void *kDoubleTapAddedKey = &kDoubleTapAddedKey;
    NSNumber *added = objc_getAssociatedObject(self, kDoubleTapAddedKey);
    if ([added boolValue]) return;

    // Remove any existing double-tap gestures (just in case)
    for (UIGestureRecognizer *gr in self.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 2) {
                [self removeGestureRecognizer:gr];
            }
        }
    }

    // Add double-tap gesture
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dd_handleDoubleTap:)];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    [self addGestureRecognizer:doubleTap];

    objc_setAssociatedObject(self, kDoubleTapAddedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    NSLog(@"DoubleTapReachability: Gesture added to home bar");
}

- (void)dd_handleDoubleTap:(UITapGestureRecognizer *)gesture {
    // Haptic feedback
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];

    // Toggle Reachability
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

%end
