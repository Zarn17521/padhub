#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/* A game built into PadHub as a framework of its own, so each emulator core
 * keeps its symbols to itself. The framework's Info.plist names a class that
 * adopts this protocol (NSPrincipalClass); PadHub loads the framework the
 * first time the game is opened and makes one instance for the whole launch.
 * Main thread only. */
@protocol PadHubGame <NSObject>

/* exitHandler brings up PadHub's menu over the game (its controllers, its
 * settings, back to PadHub). The game calls it from its own menu and on the
 * controller's HOME button. */
- (instancetype)initWithExitHandler:(void (^)(void))exitHandler;

/* The game's screen. PadHub shows it in a window of its own. The game starts
 * at once, without a title or settings screen of its own. */
@property(nonatomic, readonly) UIViewController *viewController;

/* The game comes to the front, or goes behind PadHub's menu, where it stays
 * paused until it comes back. */
- (void)resume;
- (void)suspend;

/* Ends the game as on a normal exit, so another game can run. The next resume
 * starts it again. */
- (void)stop;

@optional
/* Like stop, but reports whether the game actually ended and freed its memory
 * in-process. A game that tears itself down (a Switch game) implements this;
 * GameHost prefers it and, when it returns NO, falls back to restarting the
 * app. A game without it is stopped with stop and assumed to have succeeded. */
- (BOOL)stopGame NS_SWIFT_NAME(stopGame());

/* Like stopGame, for a game that can only end once PadHub's own call has
 * returned (Wind Waker, whose loop owns the main thread): completion runs on
 * the main queue once it has ended, with NO when it could not. GameHost waits
 * for it before starting another game. */
- (void)stopGameWithCompletion:(void (^)(BOOL stopped))completion NS_SWIFT_NAME(stopGame(completion:));

/* NO once the game has ended and cannot start again before PadHub restarts.
 * YES when absent. */
@property(nonatomic, readonly) BOOL canStartAgain;

/* Imports a disc image the player put in PadHub's Import folder, as the
 * game's own import does. The game is in front. */
- (void)importDiscAtURL:(NSURL *)url;

/* NO for a game that cannot end once it has run: PadHub then restarts to
 * start another game. YES when absent. */
@property(nonatomic, readonly) BOOL canStop;

/* The game's own settings, for PadHub to show whether or not the game is
 * running; done is called once the player closes them. Choices the game reads
 * when it starts apply the next time it starts (settingsNeedRestart). */
+ (nullable UIViewController *)settingsViewControllerWithDone:(void (^)(void))done;
@property(class, nonatomic, readonly) BOOL settingsNeedRestart;

/* The game's own button mapping, shown over the game. */
- (void)showControllerMapping;

/* For PadHub's launch screen, before the game starts or resumes: YES, and
 * handler is called on the main thread once the game shows its first frame
 * or needs the player instead; NO when there is nothing to wait for (it is
 * already running, or shows a screen of its own first). */
- (BOOL)waitForStartup:(void (^)(void))handler;

@end

NS_ASSUME_NONNULL_END
