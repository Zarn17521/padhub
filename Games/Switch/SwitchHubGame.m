#import "PadHubGame.h"

#import <UIKit/UIKit.h>

// nxnative's iOS front end (dm/ios/Sources main.m, front_ios.m and DmGamepad.m), built with
// DM_EMBEDDED=1.
NSBundle *dm_ios_bundle(void);
void dm_ios_set_data_dir(NSString *dir);
int dm_ios_boot_env(void);
UIViewController *front_ios_root(void);
void front_ios_focus_event(int ev);
void front_ios_set_host_overlay(UIView *view);
void front_ios_reclaim(void);
void dm_gamepad_set_home_handler(void (^handler)(void));
void *dm_launcher_settings_controller(void (^done)(void));  // Launcher.swift, +1

/* A Switch game built with nxnative, inside PadHub. The framework carries the game's code and tables;
 * its game files (romfs.img) and shader libraries (msl) live in its own data folder, Library/
 * Application Support/Switch/<title ID>, put there once from a Mac. Going behind PadHub's menu is
 * what going to the background is for the game. It cannot end (canStop): it waits, paused, while
 * a GameCube game runs, and PadHub restarts to start another Switch game. */
@interface SwitchHubGame : NSObject <PadHubGame>
@end

@implementation SwitchHubGame {
    UIViewController *_viewController;
    UIButton *_homeButton;
    BOOL _inFront;
    BOOL _behindMenu;  // focus events 0 and 1 sent
}

- (instancetype)initWithExitHandler:(void (^)(void))exitHandler {
    if ((self = [super init])) {
        NSString *title = [dm_ios_bundle() objectForInfoDictionaryKey:@"DMTitleID"];
        NSString *support = NSSearchPathForDirectoriesInDomains(
            NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
        dm_ios_set_data_dir([[support stringByAppendingPathComponent:@"Switch"]
            stringByAppendingPathComponent:title]);
        dm_ios_boot_env();
        // No settings screen before the game: it starts with the saved choices, and PadHub shows
        // the settings (settingsViewControllerWithDone:).
        setenv("DM_LAUNCHER", "0", 1);

        void (^exitToHub)(void) = [exitHandler copy];
        __weak SwitchHubGame *weakSelf = self;
        dm_gamepad_set_home_handler(^{
            SwitchHubGame *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf->_inFront)
                exitToHub();
        });
        _viewController = front_ios_root();

        // The touch controls have no menu: a small button brings up PadHub's.
        _homeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _homeButton.frame = CGRectMake(0, 0, 34, 34);
        [_homeButton setImage:[UIImage systemImageNamed:@"house.fill"] forState:UIControlStateNormal];
        _homeButton.tintColor = UIColor.whiteColor;
        _homeButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
        _homeButton.layer.cornerRadius = 17;
        _homeButton.alpha = 0.7;
        _homeButton.accessibilityLabel = @"PadHub menu";
        [_homeButton addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            (void)action;
            exitToHub();
        }] forControlEvents:UIControlEventTouchUpInside];
        front_ios_set_host_overlay(_homeButton);  // the root view controller keeps it on top

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

- (UIViewController *)viewController {
    return _viewController;
}

- (BOOL)canStop {
    return NO;
}

+ (UIViewController *)settingsViewControllerWithDone:(void (^)(void))done {
    return (__bridge_transfer UIViewController *)dm_launcher_settings_controller(done);
}

+ (BOOL)settingsNeedRestart {
    return YES;
}

- (void)resume {
    [_viewController loadViewIfNeeded];
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

- (void)stop {
    [self suspend];
}

#pragma mark - The app going to the background while the game is in front

- (void)sceneWillDeactivate:(NSNotification *)notification {
    (void)notification;
    if (_inFront)
        front_ios_focus_event(0);
}

- (void)sceneDidEnterBackground:(NSNotification *)notification {
    (void)notification;
    if (_inFront)
        front_ios_focus_event(1);
}

- (void)sceneWillEnterForeground:(NSNotification *)notification {
    (void)notification;
    if (_inFront)
        front_ios_focus_event(2);
}

- (void)sceneDidActivate:(NSNotification *)notification {
    (void)notification;
    if (_inFront)
        front_ios_focus_event(3);
}

@end
