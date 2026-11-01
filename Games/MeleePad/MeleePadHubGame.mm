#import "PadHubGame.h"

#import "MeleePadDiagnostics.h"
#import "MeleePadGameOverlay.h"
#import "MeleePadGameViewController.h"
#import "MeleePadNSOGCBridge.h"

// MeleePad's own import, which its file picker uses too, and its button mapping.
@interface MeleePadGameViewController (PadHubImport)
- (void)importGameDataFromURL:(NSURL *)url;
- (void)presentControllerMapping;
@end

/* MeleePad inside PadHub: what MeleePad's app delegate does for the
 * standalone app, with PadHub's menu deciding when the game is in front.
 * PadHub's data container starts empty, so the preference migrations of older
 * MeleePad builds have nothing to do here. */
@interface MeleePadHubGame : NSObject <PadHubGame>
@end

@implementation MeleePadHubGame {
    MeleePadGameViewController *_viewController;
    BOOL _inFront;
    BOOL _stopped;
    BOOL _started;  // showed its first frame (or needed the player) since its last start
    UIBackgroundTaskIdentifier _saveFlushTask;
}

- (instancetype)initWithExitHandler:(void (^)(void))exitHandler {
    if ((self = [super init])) {
        MeleePadDiagnosticsStart();
        _saveFlushTask = UIBackgroundTaskInvalid;
        void (^exitToHub)(void) = [exitHandler copy];
        MeleePadGameOverlay.hostMenuElements = @[
            [UIAction actionWithTitle:@"PadHub Menu"
                                image:[UIImage systemImageNamed:@"house.fill"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {
                (void)action;
                exitToHub();
            }],
        ];
        __weak MeleePadHubGame *weakSelf = self;
        [MeleePadNSOGCBridge sharedBridge].homeButtonHandler = ^{
            MeleePadHubGame *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf->_inFront)
                exitToHub();
        };
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(sceneWillDeactivate:)
                       name:UISceneWillDeactivateNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidActivate:)
                       name:UISceneDidActivateNotification object:nil];
        _viewController = [[MeleePadGameViewController alloc] init];
        // PadHub's menu is the home screen: Melee starts at once.
        _viewController.playsWithoutHome = YES;
        MeleePadLog(@"hub game made host=PadHub");
    }
    return self;
}

- (UIViewController *)viewController {
    return _viewController;
}

- (void)resume {
    // Boots Melee and connects its controllers the first time.
    [_viewController loadViewIfNeeded];
    _inFront = YES;
    if (_stopped) {
        _stopped = NO;
        [_viewController playFromHome];
    }
    // PadHub's menu used the NSO controllers meanwhile.
    [[MeleePadNSOGCBridge sharedBridge] start];
    [_viewController resumeRuntimeForApplicationLifecycle];
    MeleePadLog(@"hub game resumed");
}

- (void)suspend {
    _inFront = NO;
    [_viewController pauseRuntimeForApplicationLifecycle];
    MeleePadLog(@"hub game suspended");
}

// Back to MeleePad's own home, unseen: the next resume plays again.
- (void)stop {
    _inFront = NO;
    _stopped = YES;
    _started = NO;
    [_viewController stopGame];
}

- (BOOL)waitForStartup:(void (^)(void))handler {
    if (_started)
        return NO;
    void (^done)(void) = [handler copy];
    __weak MeleePadHubGame *weakSelf = self;
    _viewController.startupHandler = ^{
        MeleePadHubGame *strongSelf = weakSelf;
        if (strongSelf != nil)
            strongSelf->_started = YES;
        done();
    };
    return YES;
}

- (void)showControllerMapping {
    [_viewController presentControllerMapping];
}

- (void)importDiscAtURL:(NSURL *)url {
    MeleePadLog(@"hub import disc=%@", url.lastPathComponent);
    [_viewController importGameDataFromURL:url];
}

#pragma mark - The app going to the background while MeleePad is in front

- (void)sceneWillDeactivate:(NSNotification *)notification {
    (void)notification;
    if (!_inFront)
        return;
    [_viewController pauseRuntimeForApplicationLifecycle];
    [self beginSaveFlushGrace];
}

- (void)sceneDidActivate:(NSNotification *)notification {
    (void)notification;
    [self endSaveFlushGraceWithReason:@"active"];
    if (_inFront)
        [_viewController resumeRuntimeForApplicationLifecycle];
}

// Dolphin's GCI-folder backend writes the memory card a second after the
// game's last save; keep the process alive long enough for it, as MeleePad's
// app delegate does.
- (void)beginSaveFlushGrace {
    UIApplication *application = UIApplication.sharedApplication;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    __weak MeleePadHubGame *weakSelf = self;
    task = [application beginBackgroundTaskWithName:@"MeleePad save flush grace"
                                  expirationHandler:^{
        MeleePadHubGame *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_saveFlushTask == task)
            [strongSelf endSaveFlushGraceWithReason:@"expired"];
    }];
    if (task == UIBackgroundTaskInvalid)
        return;
    [self endSaveFlushGraceWithReason:@"replaced"];
    _saveFlushTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        MeleePadHubGame *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_saveFlushTask == task)
            [strongSelf endSaveFlushGraceWithReason:@"timer"];
    });
}

- (void)endSaveFlushGraceWithReason:(NSString *)reason {
    if (_saveFlushTask == UIBackgroundTaskInvalid)
        return;
    [UIApplication.sharedApplication endBackgroundTask:_saveFlushTask];
    _saveFlushTask = UIBackgroundTaskInvalid;
    MeleePadLog(@"lifecycle save flush grace ended reason=%@", reason);
}

@end
