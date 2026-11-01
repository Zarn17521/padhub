#import "PadHubGame.h"

#import <UIKit/UIKit.h>

// nxnative's iOS front end (dm/ios/Sources main.m, front_ios.m and DmGamepad.m), built with
// DM_EMBEDDED=1.
NSBundle *dm_ios_bundle(void);
void dm_ios_snapshot(void);
void dm_ios_set_data_dir(NSString *dir);
int dm_ios_boot_env(void);
int dm_ios_stop(double timeout_s);
UIViewController *front_ios_root(void);
void front_ios_focus_event(int ev);
void front_ios_set_host_overlay(UIView *view);
void front_ios_reclaim(void);
void dm_gamepad_set_home_handler(void (^handler)(void));
void *dm_launcher_settings_controller(void (^done)(void));  // Launcher.swift, +1

/* A Switch game built with nxnative, inside PadHub. The framework carries the game's code and tables;
 * its game files (romfs.img) and shader libraries (msl) live in its own data folder, Library/
 * Application Support/Switch/<title ID>, put there once from a Mac. Going behind PadHub's menu is
 * what going to the background is for the game. It can now end in-process (dm_ios_stop): quitting it,
 * or starting another game, stops it and frees its memory, and a later start boots it again from
 * scratch without the app restarting. If the stop cannot finish safely, stopGame reports NO and
 * PadHub restarts the app, as it did before. */
@interface SwitchHubGame : NSObject <PadHubGame>
@end

@implementation SwitchHubGame {
    UIViewController *_viewController;
    UIButton *_homeButton;
    void (^_exitToHub)(void);
    BOOL _inFront;
    BOOL _behindMenu;  // focus events 0 and 1 sent
    BOOL _stopped;     // dm_ios_stop ran; the next viewController access boots the game again
}

- (instancetype)initWithExitHandler:(void (^)(void))exitHandler {
    if ((self = [super init])) {
        // Before any nxnative code runs: copy the framework's writable C state, so a stop can put it
        // back and the next start is a fresh boot (dm/ios/Sources/main.m).
        dm_ios_snapshot();

        _exitToHub = [exitHandler copy];

        // The touch controls have no menu: a small button brings up PadHub's. Made once; it outlives
        // a stop (front_ios_set_host_overlay points the game's view at it again at each start).
        _homeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _homeButton.frame = CGRectMake(0, 0, 34, 34);
        [_homeButton setImage:[UIImage systemImageNamed:@"house.fill"] forState:UIControlStateNormal];
        _homeButton.tintColor = UIColor.whiteColor;
        _homeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _homeButton.layer.cornerRadius = 17;
        _homeButton.alpha = 0.7;
        _homeButton.accessibilityLabel = @"PadHub menu";
        __weak SwitchHubGame *weakSelf = self;
        [_homeButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            (void)action;
            SwitchHubGame *strongSelf = weakSelf;
            if (strongSelf != nil) strongSelf->_exitToHub();
        }] forControlEvents:UIControlEventTouchUpInside];

        [self boot];

        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(sceneWillDeactivate:)
                       name:UISceneWillDeactivateNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidEnterBackground:)
                       name:UISceneDidEnterBackgroundNotification object:nil];
        [center addObserver:self selector:@selector(sceneWillEnterForeground:)
                       name:UISceneWillEnterForegroundNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidActivate:)
                       name:UISceneDidActivateNotification object:nil];
    }
    return self;
}

// A fresh start of the game: the data folder, the environment, a root view controller and the host
// controls. The same steps run at the first start and after a stop (the framework's statics are back
// to their load-time values, so dm_ios_boot_env boots again).
- (void)boot {
    // The environment and signal handlers as other games left them, for the stop to put back (the
    // statics were copied once, in init).
    dm_ios_snapshot();
    NSString *title = [dm_ios_bundle() objectForInfoDictionaryKey:@"DMTitleID"];
    NSString *support = NSSearchPathForDirectoriesInDomains(
        NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    dm_ios_set_data_dir([[support stringByAppendingPathComponent:@"Switch"]
        stringByAppendingPathComponent:title]);
    dm_ios_boot_env();
    // No settings screen before the game: it starts with the saved choices, and PadHub shows the
    // settings (settingsViewControllerWithDone:).
    setenv("DM_LAUNCHER", "0", 1);

    __weak SwitchHubGame *weakSelf = self;
    dm_gamepad_set_home_handler(^{
        SwitchHubGame *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_inFront)
            strongSelf->_exitToHub();
    });
    _viewController = front_ios_root();
    front_ios_set_host_overlay(_homeButton);  // the root view controller keeps it on top
    _behindMenu = NO;
    _stopped = NO;
}

- (UIViewController *)viewController {
    if (_stopped) [self boot];  // reopened after a stop: boot again, so PadHub shows the new screen
    return _viewController;
}

- (BOOL)canStop {
    return YES;
}

+ (UIViewController *)settingsViewControllerWithDone:(void (^)(void))done {
    return (__bridge_transfer UIViewController *)dm_launcher_settings_controller(done);
}

+ (BOOL)settingsNeedRestart {
    return YES;
}

- (void)resume {
    [self.viewController loadViewIfNeeded];
    _inFront = YES;
    if (_behindMenu) {
        _behindMenu = NO;
        front_ios_reclaim();  // another game may have run meanwhile
        front_ios_focus_event(2);
        front_ios_focus_event(3);  // also takes the NSO controllers back from PadHub's menu
    }
}

- (void)suspend {
    _inFront = NO;
    if (!_behindMenu) {
        _behindMenu = YES;
        front_ios_focus_event(0);
        front_ios_focus_event(1);
    }
}

// Quit the game, freeing its memory. It is first sent to the background (suspend), then stopped on
// the main thread. YES once it has stopped and a later start can boot it again; NO when the stop
// could not finish safely, so PadHub falls back to restarting the app.
- (BOOL)stopGame {
    if (_stopped) return YES;
    [self suspend];
    if (!dm_ios_stop(8.0)) return NO;
    _inFront = NO;
    _stopped = YES;
    _viewController = nil;
    return YES;
}

// The protocol's plain stop: PadHub prefers stopGame (it reports whether the stop worked); this is
// here for callers that do not, and for a game that cannot stop it would only suspend.
- (void)stop {
    [self stopGame];
}

#pragma mark - The app going to the background while the game is in front

- (void)sceneWillDeactivate:(NSNotification *)notification {
    (void)notification;
    if (_inFront && !_stopped)
        front_ios_focus_event(0);
}

- (void)sceneDidEnterBackground:(NSNotification *)notification {
    (void)notification;
    if (_inFront && !_stopped)
        front_ios_focus_event(1);
}

- (void)sceneWillEnterForeground:(NSNotification *)notification {
    (void)notification;
    if (_inFront && !_stopped)
        front_ios_focus_event(2);
}

- (void)sceneDidActivate:(NSNotification *)notification {
    (void)notification;
    if (_inFront && !_stopped)
        front_ios_focus_event(3);
}

@end
