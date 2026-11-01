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
#include <atomic>
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
// GXRuntime's Aurora backend: set, the game's loop ends at its next turn and runs its teardown (BlueWake main.c).
namespace gx_aurora {
extern bool g_should_quit;
}

/* BlueWake's Wind Waker inside PadHub. The game's loop owns the main thread once it has started: PadHub
 * starts it from a run-loop timer, and PadHub's own screens then run inside it, each time the game hands
 * UIKit its events. The game draws in SDL's own window, which hides behind PadHub's menu (a picture of the
 * paused game stands in) and comes back on resume. Stopping it ends its loop as quitting the BlueWake app
 * does (the memory card is written, the renderer and audio shut down); that happens once PadHub's own call
 * returns into the loop. It does not start again in the same process: PadHub restarts for that
 * (canStartAgain). If PadHub closes while the game runs, an exit handler writes the memory card first. NSO
 * GameCube controllers reach the game as GameCube pads (each controller's player is its port), and their
 * HOME button brings up PadHub's menu. */
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
    BOOL _firstFrame;  // the game has drawn (PadHub's launch screen can go)
    NSTimer *_firstFrameTimer;
    BOOL _stopping;  // the loop is asked to end
    BOOL _ended;     // the loop has ended: the game cannot start again before PadHub restarts
    void (^_stopCompletion)(BOOL stopped);
    std::atomic<bool> _inFront;     // read on the Bluetooth queue
    std::atomic<uint32_t> _homeDown;  // players whose NSO controller has HOME down
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
    return YES;
}

- (BOOL)canStartAgain {
    return !_ended && !_stopping;
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
    [self stopGameWithCompletion:^(BOOL stopped) {
        (void)stopped;
    }];
}

// The loop ends once PadHub's call has returned into it; completion runs after its teardown.
- (void)stopGameWithCompletion:(void (^)(BOOL stopped))completion {
    [self suspend];
    if (!_started || _ended) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES);
        });
        return;
    }
    _stopCompletion = [completion copy];
    if (_stopping)
        return;
    NSLog(@"[padhub] Wind Waker asked to end");
    _stopping = YES;
    gx_aurora::g_should_quit = true;
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

// PadHub's launch screen stays until the game draws. The first-run screen, which prepares the disc
// the first time, is a screen of its own.
- (BOOL)waitForStartup:(void (^)(void))handler {
    if (_firstFrame || _ended || _stopping)
        return NO;
    NSString *dol = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject
        stringByAppendingPathComponent:@"BlueWake"] stringByAppendingPathComponent:@"main.dol"];
    if (![NSFileManager.defaultManager fileExistsAtPath:dol])
        return NO;
    void (^done)(void) = [handler copy];
    [_firstFrameTimer invalidate];
    __weak BlueWakeHubGame *weakSelf = self;
    _firstFrameTimer = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        BlueWakeHubGame *strongSelf = weakSelf;
        if (strongSelf == nil || strongSelf->_ended || bluewake_fps_display() > 0.f || bluewake_fps_game() > 0.f) {
            [timer invalidate];
            if (strongSelf != nil)
                strongSelf->_firstFrame = YES;
            done();
        }
    }];
    return YES;
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
    // PadHub's stop, a bounded run or a fatal stop: the game cannot start again in this process.
    NSLog(@"[padhub] Wind Waker ended status=%d", status);
    [_guideWatchTimer invalidate];
    _guideWatchTimer = nil;
    _ended = YES;
    _inFront = NO;
    if (_stopCompletion != nil) {
        // Outside the game's frames, once this timer callout has returned.
        void (^completion)(BOOL) = _stopCompletion;
        _stopCompletion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(YES);
        });
    } else if (!_stopping) {
        _exitToHub();
    }
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
    // Reports set the GameCube pads from the Bluetooth queue, so the game's next read sees them: on
    // the main queue they waited for the game's loop to hand UIKit its events, up to a frame.
    manager.deliversInputOnBluetoothQueue = YES;
    manager.delegate = self;
    for (NSOGCController *controller in manager.controllers)
        [self listenTo:controller];
    // HOME, still down from bringing the game back, is not a new press.
    uint32_t homeDown = 0;
    for (NSOGCController *controller in manager.controllers)
        if (controller.playerIndex >= 0 && (controller.state.buttons & NSOGC_BUTTON_HOME))
            homeDown |= 1u << controller.playerIndex;
    _homeDown.store(homeDown);
    [manager start];
    bluewake_shell_set_external_controller(manager.controllers.count > 0);
}

- (void)listenTo:(NSOGCController *)controller {
    __weak BlueWakeHubGame *weakSelf = self;
    controller.inputHandler = ^(NSOGCController *c, nsogc_state state) {
        [weakSelf controller:c changedTo:state];
    };
}

// The Bluetooth queue. The game reads its pads on the main thread; a read that overlaps a write can
// only mix this report with the last one, for that read.
- (void)controller:(NSOGCController *)controller changedTo:(nsogc_state)state {
    const NSInteger player = controller.playerIndex;
    if (player < 0 || player >= PAD_CHANMAX)
        return;
    const uint32_t bit = 1u << player;
    const BOOL home = (state.buttons & NSOGC_BUTTON_HOME) != 0;
    const uint32_t before = home ? _homeDown.fetch_or(bit) : _homeDown.fetch_and(~bit);
    const BOOL pressed = home && !(before & bit);
    if (!_inFront.load())
        return;
    if (pressed) {
        void (^exitToHub)(void) = _exitToHub;
        dispatch_async(dispatch_get_main_queue(), exitToHub);
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
    controller.inputHandler = nil;
    if (controller.playerIndex >= 0 && controller.playerIndex < PAD_CHANMAX)
        PADClearVirtualStatus((u32)controller.playerIndex);
    BOOL others = NO;
    for (NSOGCController *c in manager.controllers)
        others = others || c != controller;
    bluewake_shell_set_external_controller(others);
}

@end
