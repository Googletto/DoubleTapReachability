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

// ----- Overlay view that handles touches -----
@interface DoubleTapOverlayView : UIView
@end

@implementation DoubleTapOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.userInteractionEnabled = YES;
        self.alpha = 0.01;

        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleTap:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.numberOfTouchesRequired = 1;
        doubleTap.cancelsTouchesInView = NO;
        doubleTap.delaysTouchesBegan = NO;
        doubleTap.delaysTouchesEnded = NO;
        [self addGestureRecognizer:doubleTap];

        writeLog(@"Overlay view created with double-tap gesture");
    }
    return self;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesBegan:touches withEvent:event];
    writeLog(@"Touch began on overlay view!");
}

- (void)handleDoubleTap:(UITapGestureRecognizer *)gesture {
    writeLog(@"Double-tap detected on overlay!");
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
    toggleReachability();
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    return YES;
}

@end

// ----- Global reference to our overlay window -----
static UIWindow *overlayWindow = nil;

// ----- Create or show the overlay window -----
void addOverlayWindow() {
    // If the window already exists and is not hidden, just keep it
    if (overlayWindow && !overlayWindow.hidden) {
        writeLog(@"Overlay window already exists and is visible.");
        return;
    }

    // If it exists but is hidden, show it again
    if (overlayWindow && overlayWindow.hidden) {
        overlayWindow.hidden = NO;
        writeLog(@"Overlay window was hidden, shown again.");
        return;
    }

    // Create a new window
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
            addOverlayWindow();
        });
        return;
    }

    overlayWindow = [[UIWindow alloc] initWithFrame:keyWindow.bounds];
    overlayWindow.windowLevel = UIWindowLevelAlert; // highest level (above everything)
    overlayWindow.backgroundColor = [UIColor clearColor];
    overlayWindow.userInteractionEnabled = YES;
    overlayWindow.hidden = NO;

    // Add overlay view at the bottom
    CGFloat height = 60;
    CGFloat y = overlayWindow.bounds.size.height - height;
    DoubleTapOverlayView *overlayView = [[DoubleTapOverlayView alloc] initWithFrame:CGRectMake(0, y, overlayWindow.bounds.size.width, height)];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    [overlayWindow addSubview:overlayView];

    writeLog(@"Overlay window created with level %f", overlayWindow.windowLevel);
}

// ----- Hook SBHomeScreenViewController to re-add overlay on every appearance -----
%hook SBHomeScreenViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    // Re-add or show overlay every time the home screen appears
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        addOverlayWindow();
    });
}

%end
