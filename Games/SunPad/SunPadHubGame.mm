#import "PadHubGame.h"

#import "SunPadDiagnostics.h"
#import "SunPadGameOverlay.h"
#import "SunPadGameViewController.h"
#import "SunPadNSOGCBridge.h"

// SunPad's own import, which its file picker uses too.
@interface SunPadGameViewController (PadHubImport)
- (void)importGameDataFromURL:(NSURL *)url;
@end

/* SunPad inside PadHub: what SunPad's app delegate does for the standalone
 * app, with PadHub's menu deciding when the game is in front. PadHub's data
 * container starts empty, so the preference migrations of older SunPad builds
 * have nothing to do here. */
@interface SunPadHubGame : NSObject <PadHubGame>
@end

@implementation SunPadHubGame {
    SunPadGameViewController *_viewController;
    BOOL _inFront;
    BOOL _stopped;
    UIBackgroundTaskIdentifier _saveFlushTask;
}

- (instancetype)initWithExitHandler:(void (^)(void))exitHandler {
    if ((self = [super init])) {
        SunPadDiagnosticsStart();
        _saveFlushTask = UIBackgroundTaskInvalid;
        void (^exitToHub)(void) = [exitHandler copy];
        SunPadGameOverlay.hostMenuElements = @[
            [UIAction actionWithTitle:@"Back to PadHub"
                                image:[UIImage systemImageNamed:@"house.fill"]
                           identifier:nil
                              handler:^(__kindof UIAction *action) {
                (void)action;
                exitToHub();
            }],
        ];
        __weak SunPadHubGame *weakSelf = self;
        [SunPadNSOGCBridge sharedBridge].homeButtonHandler = ^{
            SunPadHubGame *strongSelf = weakSelf;
            if (strongSelf != nil && strongSelf->_inFront)
                exitToHub();
        };
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        [center addObserver:self selector:@selector(sceneWillDeactivate:)
                       name:UISceneWillDeactivateNotification object:nil];
        [center addObserver:self selector:@selector(sceneDidActivate:)
                       name:UISceneDidActivateNotification object:nil];
        _viewController = [[SunPadGameViewController alloc] init];
        SunPadLog(@"hub game made host=PadHub");
    }
    return self;
}

- (UIViewController *)viewController {
    return _viewController;
}

- (void)resume {
    // Boots the game and connects its controllers the first time.
    [_viewController loadViewIfNeeded];
    _inFront = YES;
    if (_stopped) {
        _stopped = NO;
        [_viewController restartGame];
    }
    // PadHub's menu used the NSO controller meanwhile.
    [[SunPadNSOGCBridge sharedBridge] start];
    [_viewController resumeRuntimeForApplicationLifecycle];
    SunPadLog(@"hub game resumed");
}

- (void)suspend {
    _inFront = NO;
    [_viewController pauseRuntimeForApplicationLifecycle];
    SunPadLog(@"hub game suspended");
}

- (void)stop {
    _inFront = NO;
    _stopped = YES;
    [_viewController stopGame];
}

- (void)importDiscAtURL:(NSURL *)url {
    SunPadLog(@"hub import disc=%@", url.lastPathComponent);
    [_viewController importGameDataFromURL:url];
}

#pragma mark - The app going to the background while SunPad is in front

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
// game's last save; keep the process alive long enough for it, as SunPad's
// app delegate does.
- (void)beginSaveFlushGrace {
    UIApplication *application = UIApplication.sharedApplication;
    __block UIBackgroundTaskIdentifier task = UIBackgroundTaskInvalid;
    __weak SunPadHubGame *weakSelf = self;
    task = [application beginBackgroundTaskWithName:@"SunPad save flush grace"
                                  expirationHandler:^{
        SunPadHubGame *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_saveFlushTask == task)
            [strongSelf endSaveFlushGraceWithReason:@"expired"];
    }];
    if (task == UIBackgroundTaskInvalid)
        return;
    [self endSaveFlushGraceWithReason:@"replaced"];
    _saveFlushTask = task;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SunPadHubGame *strongSelf = weakSelf;
        if (strongSelf != nil && strongSelf->_saveFlushTask == task)
            [strongSelf endSaveFlushGraceWithReason:@"timer"];
    });
}

- (void)endSaveFlushGraceWithReason:(NSString *)reason {
    if (_saveFlushTask == UIBackgroundTaskInvalid)
        return;
    [UIApplication.sharedApplication endBackgroundTask:_saveFlushTask];
    _saveFlushTask = UIBackgroundTaskInvalid;
    SunPadLog(@"lifecycle save flush grace ended reason=%@", reason);
}

@end
