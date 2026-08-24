#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ----- Logging helper (file-toggle) -----
static NSString *logFilePath = @"/var/mobile/Documents/DoubleTapReachability.log";
static NSString *debugFlagPath = @"/var/mobile/Documents/DoubleTapReachability.debug";

void writeLog(NSString *format, ...) {
    if (![[NSFileManager defaultManager] fileExistsAtPath:debugFlagPath]) return;
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dir = [logFilePath stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:dir]) {
        [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
    NSString *timestamp = [df stringFromDate:[NSDate date]];
    NSString *logLine = [NSString stringWithFormat:@"[%@] %@\n", timestamp, message];

    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:logFilePath];
    if (!fh) {
        [logLine writeToFile:logFilePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        [fh seekToEndOfFile];
        [fh writeData:[logLine dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
    NSLog(@"%@", message);
}

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

// ----- Custom gesture delegate -----
@interface DoubleTapGestureDelegate : NSObject <UIGestureRecognizerDelegate>
@end
@implementation DoubleTapGestureDelegate
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return YES;
}
@end

// ----- Helper functions -----
void findHomeGrabberInView(UIView *view, UIView **outView) {
    if (*outView) return;
    if ([view isKindOfClass:NSClassFromString(@"SBHomeGrabberView")] ||
        [view isKindOfClass:NSClassFromString(@"_SBHomeGrabberView")]) {
        *outView = view;
        return;
    }
    for (UIView *subview in view.subviews) {
        findHomeGrabberInView(subview, outView);
        if (*outView) return;
    }
}

void attachGestureToView(UIView *view, id target, SEL action) {
    for (UIGestureRecognizer *gr in view.gestureRecognizers) {
        if ([gr isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tap = (UITapGestureRecognizer *)gr;
            if (tap.numberOfTapsRequired == 2) {
                [view removeGestureRecognizer:gr];
                writeLog(@"Removed existing double-tap gesture");
            }
        }
    }

    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:target action:action];
    doubleTap.numberOfTapsRequired = 2;
    doubleTap.numberOfTouchesRequired = 1;
    doubleTap.cancelsTouchesInView = NO;
    doubleTap.delaysTouchesBegan = NO;
    doubleTap.delaysTouchesEnded = NO;

    static DoubleTapGestureDelegate *delegate = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        delegate = [[DoubleTapGestureDelegate alloc] init];
    });
    doubleTap.delegate = delegate;

    [view addGestureRecognizer:doubleTap];
    writeLog(@"Gesture attached to home bar with simultaneous delegate!");
}

void toggleReachability() {
    writeLog(@"Toggling Reachability...");
    NSArray *classNames = @[@"SBReachabilityManager", @"SBReachabilityController"];
    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) continue;
        id manager = [cls performSelector:@selector(sharedInstance)];
        if (!manager) continue;

        if ([manager respondsToSelector:@selector(toggleReachability)]) {
            [manager performSelector:@selector(toggleReachability)];
            writeLog(@"Used toggleReachability on %@", className);
            return;
        }

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
            writeLog(@"Used activateReachability: on %@", className);
            return;
        }

        if ([manager respondsToSelector:@selector(isReachabilityActive)]) {
            BOOL active = [[manager performSelector:@selector(isReachabilityActive)] boolValue];
            if (active) {
                if ([manager respondsToSelector:@selector(deactivateReachability)]) {
                    [manager performSelector:@selector(deactivateReachability)];
                    writeLog(@"Used deactivateReachability on %@", className);
                    return;
                }
            } else {
                if ([manager respondsToSelector:@selector(activateReachability)]) {
                    [manager performSelector:@selector(activateReachability)];
                    writeLog(@"Used activateReachability on %@", className);
                    return;
                }
            }
        }
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.apple.reachability.toggle"),
                                         NULL, NULL, YES);
    writeLog(@"Used Darwin notification fallback");
}

void addDoubleTapToHomeBar(id self) {
    UIWindow *keyWindow = nil;
    if ([UIApplication sharedApplication].delegate && [[UIApplication sharedApplication].delegate respondsToSelector:@selector(window)]) {
        keyWindow = [[UIApplication sharedApplication].delegate window];
    }
    if (!keyWindow) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        keyWindow = [UIApplication sharedApplication].windows.firstObject;
#pragma clang diagnostic pop
    }
    if (!keyWindow) {
        writeLog(@"No keyWindow, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            addDoubleTapToHomeBar(self);
        });
        return;
    }

    UIView *homeBar = nil;
    findHomeGrabberInView(keyWindow, &homeBar);

    if (homeBar) {
        attachGestureToView(homeBar, self, @selector(handleDoubleTap:));
    } else {
        writeLog(@"Home bar not found, retrying...");
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            addDoubleTapToHomeBar(self);
        });
    }
}

// ----- Hook SBHomeScreenViewController -----
%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            addDoubleTapToHomeBar(self);
        });
    });
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    writeLog(@"Double-tap detected!");
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    toggleReachability();
}

%end
