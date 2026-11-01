#import "PadHubGame.h"

#import <NSOGCKit/NSOGCKit.h>
#import <UIKit/UIKit.h>

#include <SDL3/SDL.h>
#define SDL_MAIN_HANDLED  // PadHub owns main()
#include <SDL3/SDL_main.h>
// The GameCube SDK types its own BOOL as an int; Objective-C's is a bool.
#define BOOL DOLPHIN_BOOL
#include <dolphin/pad.h>
#undef BOOL
#include <math.h>
#include <stdlib.h>
#include <unistd.h>

extern "C" {
#include "card_runtime.h"
}
#include "touch_controls.h"

// BlueWake (apple/ios/src): the app's entry, built for a host app (BLUEWAKE_PADHUB), and the ⋯ menu's items for
// the host.
extern "C" int bluewake_padhub_main(int argc, char **argv);
extern "C" void bluewake_shell_set_host_menu(NSArray<UIMenuElement *> *items);

/* BlueWake's Wind Waker inside PadHub. The game's loop owns the main thread once it has started: PadHub
 * starts it from a run-loop timer, and PadHub's own screens then run inside it, each time the game hands
 * UIKit its events. The game draws in SDL's own window, which hides behind PadHub's menu (a picture of the
 * paused game stands in) and comes back on resume. It cannot end before the process does (canStop): when
 * PadHub closes, an exit handler writes the memory card out first. NSO GameCube controllers reach the game
 * as GameCube pads (each controller's player is its port), and their HOME button brings up PadHub's menu. */
@interface BlueWakeHubGame : NSObject <PadHubGame, NSOGCManagerDelegate>
@end

// exit() would run the C++ destructors of objects the game's threads still use.
static void bw_hub_exit(void) {
    bluewake_card_runtime_close();
    _exit(0);
}

static s8 bw_axis(float value) {
    // GameCube sticks read about ±100 at full tilt, as the touch controls send them.
    long v = lrintf(fmaxf(-1.f, fminf(1.f, value)) * 100.f);
    return (s8)v;
}

static u8 bw_trigger(float value) {
    return (u8)lrintf(fmaxf(0.f, fminf(1.f, value)) * 255.f);
}

static bool SDLCALL bw_guide_watch(void *userdata, SDL_Event *event) {
    if (event->type == SDL_EVENT_GAMEPAD_BUTTON_DOWN && event->gbutton.button == SDL_GAMEPAD_BUTTON_GUIDE) {
        void (^exitToHub)(void) = (__bridge void (^)(void))userdata;
        dispatch_async(dispatch_get_main_queue(), exitToHub);
    }
    return true;
}

@implementation BlueWakeHubGame {
    void (^_exitToHub)(void);
    UIViewController *_viewController;
    UIView *_pausedPicture;
    NSTimer *_guideWatchTimer;
    BOOL _started;
    BOOL _inFront;
    uint32_t _homeDown;  // players whose NSO controller has HOME down
}

- (instancetype)initWithExitHandler:(void (^)(void))exitHandler {
    if ((self = [super init])) {
        _exitToHub = [exitHandler copy];
        _viewController = [UIViewController new];
        _viewController.view.backgroundColor = UIColor.blackColor;
        // The module made from the player's disc sits at the top of PadHub.app, as the GameCube games' do.
        NSString *module = [NSBundle.mainBundle.bundlePath stringByAppendingPathComponent:@"gGZLE01_recomp.dylib"];
        setenv("BLUEWAKE_COMPOSITE", module.fileSystemRepresentation, 1);
        void (^exitToHub)(void) = _exitToHub;
        bluewake_shell_set_host_menu(@[
            [UIAction actionWithTitle:@"PadHub Menu"
                                image:[UIImage systemImageNamed:@"house.fill"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {
                (void)action;
                exitToHub();
            }],
        ]);
    }
    return self;
}

- (UIViewController *)viewController {
    return _viewController;
}

- (BOOL)canStop {
    return NO;
}

- (void)resume {
    _inFront = YES;
    [self takeNSOControllers];
    if (!_started) {
        _started = YES;
        // From a run-loop timer rather than inside PadHub's call: the game's loop does not return, and the
        // main queue only drains inside it when no block of that queue is running.
        [self performSelector:@selector(runGame) withObject:nil afterDelay:0];
        return;
    }
    [_pausedPicture removeFromSuperview];
    _pausedPicture = nil;
    [[self gameWindow] makeKeyAndVisible];
    bluewake_pause_set(BLUEWAKE_PAUSE_HOST, false);
}

- (void)suspend {
    _inFront = NO;
    bluewake_pause_set(BLUEWAKE_PAUSE_HOST, true);
    bluewake_touch_clear();
    for (u32 port = 0; port < PAD_CHANMAX; port++)
        PADClearVirtualStatus(port);
    UIWindow *window = [self gameWindow];
    if (window != nil && !window.hidden) {
        // The game's last picture under PadHub's menu, while SDL's window is out of the way.
        [_pausedPicture removeFromSuperview];
        _pausedPicture = [window snapshotViewAfterScreenUpdates:NO];
        _pausedPicture.frame = _viewController.view.bounds;
        _pausedPicture.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_viewController.view addSubview:_pausedPicture];
        window.hidden = YES;
    }
}

- (void)stop {
    [self suspend];
}

- (void)importDiscAtURL:(NSURL *)url {
    // Before the game first starts, its first-run screen prepares the disc it finds in its folder.
    NSString *folder = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"BlueWake"];
    NSString *disc = [folder stringByAppendingPathComponent:@"GZLE01.iso"];
    NSFileManager *files = NSFileManager.defaultManager;
    if ([files fileExistsAtPath:disc])
        return;
    [files createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    NSError *error = nil;
    if (![files moveItemAtPath:url.path toPath:disc error:&error])
        NSLog(@"[padhub] Wind Waker disc not moved: %@", error.localizedDescription);
}

#pragma mark - The game's loop

- (void)runGame {
    atexit(bw_hub_exit);
    SDL_SetMainReady();
    SDL_SetiOSEventPump(true);
    // Another controller's HOME (Guide) button, once SDL's events are up.
    __weak BlueWakeHubGame *weakSelf = self;
    _guideWatchTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *timer) {
        BlueWakeHubGame *strongSelf = weakSelf;
        if (strongSelf == nil || !SDL_WasInit(SDL_INIT_EVENTS))
            return;
        [timer invalidate];
        SDL_AddEventWatch(bw_guide_watch, (__bridge void *)strongSelf->_exitToHub);
    }];
    char name[] = "BlueWake";
    char *argv[] = {name, NULL};
    const int status = bluewake_padhub_main(1, argv);
    // Only a bounded run or a fatal stop gets here; the game cannot start again in this process.
    NSLog(@"[padhub] Wind Waker ended status=%d", status);
    _inFront = NO;
    _exitToHub();
}

- (UIWindow *)gameWindow {
    if (!SDL_WasInit(SDL_INIT_VIDEO))
        return nil;
    int count = 0;
    SDL_Window **windows = SDL_GetWindows(&count);
    UIWindow *window = nil;
    if (windows != NULL && count > 0)
        window = (__bridge UIWindow *)SDL_GetPointerProperty(SDL_GetWindowProperties(windows[0]),
                                                             SDL_PROP_WINDOW_UIKIT_WINDOW_POINTER, NULL);
    SDL_free(windows);
    return window;
}

#pragma mark - NSO GameCube controllers

- (void)takeNSOControllers {
    NSOGCManager *manager = NSOGCManager.sharedManager;
    manager.maximumControllers = 4;
    manager.deliversInputOnBluetoothQueue = NO;  // the game reads its pads on the main thread
    manager.delegate = self;
    for (NSOGCController *controller in manager.controllers)
        [self listenTo:controller];
    // HOME, still down from bringing the game back, is not a new press.
    _homeDown = 0;
    for (NSOGCController *controller in manager.controllers)
        if (controller.playerIndex >= 0 && (controller.state.buttons & NSOGC_BUTTON_HOME))
            _homeDown |= 1u << controller.playerIndex;
    [manager start];
    bluewake_shell_set_external_controller(manager.controllers.count > 0);
}

- (void)listenTo:(NSOGCController *)controller {
    __weak BlueWakeHubGame *weakSelf = self;
    controller.inputHandler = ^(NSOGCController *c, nsogc_state state) {
        [weakSelf controller:c changedTo:state];
    };
}

- (void)controller:(NSOGCController *)controller changedTo:(nsogc_state)state {
    const NSInteger player = controller.playerIndex;
    if (player < 0 || player >= PAD_CHANMAX)
        return;
    const uint32_t bit = 1u << player;
    const BOOL home = (state.buttons & NSOGC_BUTTON_HOME) != 0;
    const BOOL pressed = home && !(_homeDown & bit);
    _homeDown = home ? _homeDown | bit : _homeDown & ~bit;
    if (!_inFront)
        return;
    if (pressed) {
        _exitToHub();
        return;
    }
    const uint32_t b = state.buttons;
    PADStatus status = {};
    if (b & NSOGC_BUTTON_A) status.button |= PAD_BUTTON_A;
    if (b & NSOGC_BUTTON_B) status.button |= PAD_BUTTON_B;
    if (b & NSOGC_BUTTON_X) status.button |= PAD_BUTTON_X;
    if (b & NSOGC_BUTTON_Y) status.button |= PAD_BUTTON_Y;
    if (b & NSOGC_BUTTON_START) status.button |= PAD_BUTTON_START;
    if (b & NSOGC_BUTTON_Z) status.button |= PAD_TRIGGER_Z;
    if (b & NSOGC_BUTTON_L) status.button |= PAD_TRIGGER_L;
    if (b & NSOGC_BUTTON_R) status.button |= PAD_TRIGGER_R;
    if (b & NSOGC_BUTTON_DPAD_UP) status.button |= PAD_BUTTON_UP;
    if (b & NSOGC_BUTTON_DPAD_DOWN) status.button |= PAD_BUTTON_DOWN;
    if (b & NSOGC_BUTTON_DPAD_LEFT) status.button |= PAD_BUTTON_LEFT;
    if (b & NSOGC_BUTTON_DPAD_RIGHT) status.button |= PAD_BUTTON_RIGHT;
    status.stickX = bw_axis(state.stick_x);
    status.stickY = bw_axis(state.stick_y);
    status.substickX = bw_axis(state.cstick_x);
    status.substickY = bw_axis(state.cstick_y);
    status.triggerLeft = bw_trigger(state.trigger_l);
    status.triggerRight = bw_trigger(state.trigger_r);
    status.analogA = (b & NSOGC_BUTTON_A) ? 255 : 0;
    status.analogB = (b & NSOGC_BUTTON_B) ? 255 : 0;
    PADSetVirtualStatus((u32)player, &status);
}

- (void)manager:(NSOGCManager *)manager didConnectController:(NSOGCController *)controller {
    [self listenTo:controller];
    bluewake_shell_set_external_controller(true);
}

- (void)manager:(NSOGCManager *)manager didDisconnectController:(NSOGCController *)controller {
    if (controller.playerIndex >= 0 && controller.playerIndex < PAD_CHANMAX)
        PADClearVirtualStatus((u32)controller.playerIndex);
    BOOL others = NO;
    for (NSOGCController *c in manager.controllers)
        others = others || c != controller;
    bluewake_shell_set_external_controller(others);
}

@end
