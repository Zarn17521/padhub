#pragma once

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/* A game built into PadHub as a framework of its own, so each emulator core
 * keeps its symbols to itself. The framework's Info.plist names a class that
 * adopts this protocol (NSPrincipalClass); PadHub loads the framework the
 * first time the game is opened and makes one instance for the whole launch.
 * Main thread only. */
@protocol PadHubGame <NSObject>

/* exitHandler brings PadHub's menu back. The game calls it from its own menu
 * and on the controller's HOME button. */
- (instancetype)initWithExitHandler:(void (^)(void))exitHandler;

/* The game's screen. PadHub shows it in a window of its own. */
@property(nonatomic, readonly) UIViewController *viewController;

/* The game comes to the front, or goes behind PadHub's menu, where it stays
 * paused until it comes back. */
- (void)resume;
- (void)suspend;

/* Ends the game as on a normal exit, so another game can run. The next resume
 * starts it again. */
- (void)stop;

@optional
/* Imports a disc image the player put in PadHub's Import folder, as the
 * game's own import does. The game is in front. */
- (void)importDiscAtURL:(NSURL *)url;

/* NO for a game that cannot end once it has run (a Switch game): PadHub then
 * restarts to start another game. YES when absent. */
@property(nonatomic, readonly) BOOL canStop;

@end

NS_ASSUME_NONNULL_END
