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

// ----- Toggle function -----
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

// ----- Overlay view that captures double-taps -----
@interface DoubleTapOverlay : UIView
@end

@implementation DoubleTapOverlay

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.alpha = 0.01; // Almost invisible, but still receives touches

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.numberOfTouchesRequired = 1;
        doubleTap.cancelsTouchesInView = NO;
        doubleTap.delaysTouchesBegan = NO;
        doubleTap.delaysTouchesEnded = NO;
        [self addGestureRecognizer:doubleTap];

        writeLog(@"Overlay created with double-tap gesture");
    }
    return self;
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    writeLog(@"Double-tap detected on overlay!");
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    toggleReachability();
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    // Only respond to touches in the bottom 50px (adjust as needed)
    return point.y > self.bounds.size.height - 50;
}

@end

// ----- Hook SBHomeScreenViewController to add overlay -----
%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            UIWindow *keyWindow = nil;
            if ([UIApplication sharedApplication].delegate && [[UIApplication sharedApplication].delegate respondsToSelector:@selector(window)]) {
                keyWindow = [[UIApplication sharedApplication].delegate window];
            }
            if (!keyWindow) {
                keyWindow = [UIApplication sharedApplication].windows.firstObject;
            }
            if (!keyWindow) {
                writeLog(@"No keyWindow, retrying...");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    [self viewDidAppear:animated]; // re-trigger
                });
                return;
            }

            // Add overlay covering the bottom area
            CGFloat height = 60; // covers home bar area
            CGFloat width = keyWindow.bounds.size.width;
            CGFloat y = keyWindow.bounds.size.height - height;
            DoubleTapOverlay *overlay = [[DoubleTapOverlay alloc] initWithFrame:CGRectMake(0, y, width, height)];
            [keyWindow addSubview:overlay];
            writeLog(@"Overlay added to keyWindow!");
        });
    });
}

%end
