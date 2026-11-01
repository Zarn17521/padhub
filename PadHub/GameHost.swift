import SwiftUI
import UIKit

/// Runs the games built into PadHub. Each core is a framework (SunPadGame,
/// MeleePadGame, one per Switch game) loaded the first time its game opens. A
/// game shows in a window above the menu. HOME (or the game's own menu) brings
/// up PadHub's menu over it, paused; from there the player goes back to the
/// game, to PadHub, or quits. A game left for PadHub waits there, paused;
/// starting another game ends it first. One game runs at a time. A game that
/// cannot end (a Switch game) waits, paused, while others run; PadHub restarts
/// to start another game of that kind, and opens it at its next launch.
@MainActor
final class GameHost: ObservableObject {
  /// The game in front, or paused behind the menu.
  @Published private(set) var current: Game?
  /// A game on its way out, until it has ended.
  @Published private(set) var ending: Game?
  /// A game that cannot end, paused while another one runs.
  @Published private(set) var parked: Game?
  @Published private(set) var inFront = false
  /// PadHub's menu over the game in front.
  @Published private(set) var showingGameMenu = false
  @Published var failure: String?

  /// The menu gives its controllers to the game, and takes them back.
  var willShowGame: (() -> Void)?
  var didReturnToMenu: (() -> Void)?
  var didImportDisc: (() -> Void)?
  /// The menu shown over a game (GameMenuView, made by PadHubApp).
  var makeGameMenu: (() -> AnyView)?
  /// The launch screen over a game that is starting (DiscBootView), until its
  /// first frame.
  var makeBootScreen: ((Game) -> AnyView)?
  let gameMenu = GameMenuModel()

  private var loaded: [String: PadHubGame] = [:]
  private var classes: [String: PadHubGame.Type] = [:]
  /// The game that cannot end, once it has run in this process.
  private var unstoppable: Game?
  private static let openAtLaunchKey = "PadHubOpenAtLaunch"
  private var window: UIWindow?
  private var gameMenuWindow: UIWindow?
  private var bootWindow: UIWindow?
  private var bootToken = 0
  private weak var menuWindow: UIWindow?

  init() {
    gameMenu.host = self
  }

  /// Opens a built-in game, or brings back the one paused behind the menu.
  /// Another game in progress ends first, as when quitting it.
  func open(_ game: Game) {
    guard let embedded = game.embedded else { return }
    if needsRestart(toOpen: game) {
      restart(toOpen: game)
      return
    }
    if let current, current.id != game.id {
      if current.id == unstoppable?.id {
        Log.write("keep \(current.id) paused to start \(game.id)")
        parked = current
      } else {
        Log.write("stop \(current.id) to start \(game.id)")
        // Once it has ended (a game that cannot stop in-process restarts the app, opening
        // `game` next), `game` starts.
        end(current, fallbackOpen: game) { [weak self] in
          if self?.current?.id == current.id { self?.current = nil }
          self?.open(game)
        }
        return
      }
      self.current = nil
    }
    if parked?.id == game.id { parked = nil }
    let instance: PadHubGame
    if let existing = loaded[game.id] {
      instance = existing
    } else {
      do {
        let type = try gameClass(of: game, embedded)
        instance = type.init(exitHandler: { [weak self] in self?.showGameMenu() })
        Log.write("loaded \(embedded.framework)")
      } catch {
        Log.write("could not load \(embedded.framework): \(error.localizedDescription)")
        failure = error.localizedDescription
        return
      }
      loaded[game.id] = instance
      if instance.canStop == false { unstoppable = game }
    }
    Log.write("open \(game.id)")
    willShowGame?()
    show(instance.viewController)
    beginBootScreen(for: game, instance)
    instance.resume()
    current = game
    inFront = true
    if let disc = DiscImports.disc(for: game), let claimed = DiscImports.claim(disc) {
      Log.write("import \(disc.lastPathComponent) into \(game.id)")
      instance.importDisc?(at: claimed)
      didImportDisc?()
    }
  }

  // MARK: PadHub's menu over the game

  /// HOME in a game, or PadHub's item in the game's own menu: the game pauses
  /// under PadHub's menu.
  func showGameMenu() {
    guard inFront, !showingGameMenu, let current, let instance = loaded[current.id],
      let content = makeGameMenu?()
    else { return }
    Log.write("game menu over \(current.id)")
    instance.suspend()
    showingGameMenu = true
    gameMenu.prepare(
      for: current, hasSettings: hasSettings(current),
      hasMapping: instance.responds(to: #selector(PadHubGame.showControllerMapping)),
      quitRestarts: current.id == unstoppable?.id)
    didReturnToMenu?()
    guard let scene = window?.windowScene else { return }
    let controller = GameMenuController(rootView: content)
    controller.game = instance.viewController
    let menu = gameMenuWindow ?? UIWindow(windowScene: scene)
    gameMenuWindow = menu
    menu.windowLevel = .normal + 2  // above the launch screen
    menu.backgroundColor = .clear
    menu.rootViewController = controller
    menu.alpha = 0
    menu.makeKeyAndVisible()
    UIView.animate(withDuration: 0.2) { menu.alpha = 1 }
  }

  /// Back to the game, where it was.
  func resumeFromGameMenu() {
    guard showingGameMenu, let current, let instance = loaded[current.id] else { return }
    Log.write("game menu closed, back to \(current.id)")
    hideGameMenu()
    willShowGame?()
    window?.makeKey()
    instance.resume()
  }

  /// The game's own button mapping, over the game running again.
  func showControllerMappingFromGameMenu() {
    guard showingGameMenu, let current, let instance = loaded[current.id] else { return }
    resumeFromGameMenu()
    instance.showControllerMapping?()
  }

  /// Quits the game in front from PadHub's menu over it, back to PadHub.
  func quitFromGameMenu() {
    guard showingGameMenu, let current else { return }
    if current.id == unstoppable?.id {
      restart(toOpen: nil)
      return
    }
    returnToMenu()
    closeCurrent()
  }

  private func hideGameMenu() {
    showingGameMenu = false
    guard let menu = gameMenuWindow else { return }
    UIView.animate(withDuration: 0.15) {
      menu.alpha = 0
    } completion: { _ in
      guard !self.showingGameMenu else { return }
      menu.isHidden = true
      menu.rootViewController = nil
    }
  }

  // MARK: Back to PadHub

  /// PadHub's menu (from the menu over the game): the game waits there,
  /// paused where it was.
  func returnToMenu() {
    guard inFront, let current, let instance = loaded[current.id] else { return }
    Log.write("back to the menu from \(current.id)")
    endBootScreen(bootToken, fade: false)
    if showingGameMenu {
      hideGameMenu()  // the game is paused already
    } else {
      instance.suspend()
    }
    inFront = false
    menuWindow?.isHidden = false
    UIView.animate(withDuration: 0.3) {
      self.window?.alpha = 0
    } completion: { _ in
      guard !self.inFront else { return }
      self.window?.isHidden = true
      self.menuWindow?.makeKey()
      // A phone held upright turns the menu back to portrait.
      self.menuWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
    didReturnToMenu?()
  }

  /// The paused game can end (a Switch game cannot).
  var canCloseCurrent: Bool {
    current.map { $0.id != unstoppable?.id } ?? false
  }

  /// A game that cannot end has run, and `game` is another one of that kind; or
  /// `game` has ended and cannot start again in this launch (Wind Waker).
  func needsRestart(toOpen game: Game) -> Bool {
    if loaded[game.id]?.canStartAgain == false { return true }
    guard let unstoppable, unstoppable.id != game.id else { return false }
    return game.keepsRunning
  }

  /// The game that cannot end, once it has run (in front, paused, or waiting
  /// while another game runs).
  var endlessGame: Game? { unstoppable }

  /// Opening `game` ends the game paused behind the menu, which the player is
  /// asked first. A game that cannot end only waits.
  func endsCurrent(toOpen game: Game) -> Bool {
    guard let current, current.id != game.id else { return false }
    return current.id != unstoppable?.id
  }

  /// Quits PadHub, which opens `game`, if any, at its next launch.
  func restart(toOpen game: Game?) {
    if let game {
      UserDefaults.standard.set(game.id, forKey: Self.openAtLaunchKey)
    }
    Log.write("restart to open \(game?.id ?? "the menu")")
    exit(0)
  }

  /// The game a restart asked for, once.
  static func takeGameToOpenAtLaunch() -> String? {
    let id = UserDefaults.standard.string(forKey: openAtLaunchKey)
    UserDefaults.standard.removeObject(forKey: openAtLaunchKey)
    return id
  }

  /// Ends the game paused behind the menu.
  func closeCurrent() {
    guard !inFront, let current, current.id != unstoppable?.id else { return }
    Log.write("close \(current.id)")
    end(current, fallbackOpen: nil) { [weak self] in
      if self?.current?.id == current.id { self?.current = nil }
    }
  }

  /// Stops a game, freeing its memory, then runs `then`. A game that stops in-process (a Switch
  /// game) reports whether it succeeded through stopGame; when it cannot, PadHub restarts the app
  /// (opening `fallbackOpen` next, or the menu). A game whose loop ends only once this call has
  /// returned (Wind Waker) reports it later, and `then` waits for it. A game with only the plain
  /// stop is assumed to have ended.
  private func end(_ game: Game, fallbackOpen: Game?, then: @escaping () -> Void) {
    guard let instance = loaded[game.id] else { return then() }
    let ended: (Bool) -> Void = { [weak self] stopped in
      guard stopped else {
        Log.write("\(game.id) could not stop in-process; restarting to recover")
        self?.restart(toOpen: fallbackOpen)
        return
      }
      Log.write("\(game.id) ended")
      then()
    }
    if instance.responds(to: #selector(PadHubGame.stopGame(completion:))) {
      ending = game
      instance.stopGame?(completion: { [weak self] stopped in
        self?.ending = nil
        ended(stopped)
      })
    } else if instance.responds(to: Selector(("stopGame"))) {  // stopGame(), not stopGame(completion:)
      ended(instance.stopGame?() == true)
    } else {
      instance.stop()
      then()
    }
  }

  // MARK: A game's own settings

  /// The game has settings PadHub can show (its framework's Info.plist says
  /// so), read without loading the game.
  func hasSettings(_ game: Game) -> Bool {
    guard let embedded = game.embedded, let bundle = Bundle(url: frameworkURL(embedded)) else { return false }
    return bundle.object(forInfoDictionaryKey: "PadHubGameSettings") as? Bool ?? false
  }

  /// Choices in the game's settings apply the next time it starts.
  func settingsNeedRestart(_ game: Game) -> Bool {
    guard let embedded = game.embedded, let type = try? gameClass(of: game, embedded) else { return false }
    return type.settingsNeedRestart ?? false
  }

  /// Shows the game's settings over PadHub's menu, or over the game.
  func showSettings(of game: Game) {
    guard let embedded = game.embedded else { return }
    let type: PadHubGame.Type
    do {
      type = try gameClass(of: game, embedded)
    } catch {
      failure = error.localizedDescription
      return
    }
    let presenter = topViewController(of: showingGameMenu ? gameMenuWindow : hubWindow())
    var shown: UIViewController?
    guard
      let settings = type.settingsViewController?(done: {
        shown?.presentingViewController?.dismiss(animated: true)
        shown = nil
      })
    else { return }
    shown = settings
    Log.write("settings of \(game.id)")
    presenter?.present(settings, animated: true)
  }

  /// Closes the game's settings, if they are open (B on a controller).
  @discardableResult
  func closeSettings() -> Bool {
    guard let presenter = topViewController(of: showingGameMenu ? gameMenuWindow : hubWindow()),
      let presenting = presenter.presentingViewController
    else { return false }
    presenting.dismiss(animated: true)
    return true
  }

  var showingSettings: Bool {
    topViewController(of: showingGameMenu ? gameMenuWindow : hubWindow())?.presentingViewController != nil
  }

  // MARK: The launch screen

  /// Puts the launch screen over a game that starts, for as long as it has
  /// not shown its first frame: until the game says so, it shows a screen of
  /// its own (an alert, a picker), or a minute has gone by.
  private func beginBootScreen(for game: Game, _ instance: PadHubGame) {
    bootToken += 1
    let token = bootToken
    var startedAlready = false
    let waiting =
      instance.wait?(forStartup: { [weak self] in
        startedAlready = true
        self?.endBootScreen(token, fade: true)
      }) ?? false
    guard waiting, !startedAlready, let content = makeBootScreen?(game), let scene = window?.windowScene
    else { return }
    Log.write("launch screen for \(game.id)")
    let boot = bootWindow ?? UIWindow(windowScene: scene)
    bootWindow = boot
    boot.windowLevel = .normal + 1  // above the game, and SDL's own window
    boot.isUserInteractionEnabled = false
    boot.backgroundColor = .clear
    let controller = GameMenuController(rootView: content)
    controller.game = instance.viewController
    boot.rootViewController = controller
    boot.alpha = 1
    boot.isHidden = false
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in
      self?.endBootScreen(token, fade: true)
    }
    watchBootScreen(token)
  }

  /// The game put up a screen of its own while starting: it goes first.
  private func watchBootScreen(_ token: Int) {
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
      guard let self, token == self.bootToken, self.bootWindow?.isHidden == false else { return }
      if self.window?.rootViewController?.presentedViewController != nil {
        self.endBootScreen(token, fade: true)
      } else {
        self.watchBootScreen(token)
      }
    }
  }

  private func endBootScreen(_ token: Int, fade: Bool) {
    guard token == bootToken, let boot = bootWindow, !boot.isHidden else { return }
    bootToken += 1  // nothing waits on this one any more
    let hide = {
      boot.isHidden = true
      boot.rootViewController = nil
      boot.alpha = 1
    }
    guard fade else { return hide() }
    UIView.animate(withDuration: 0.5, animations: { boot.alpha = 0 }) { _ in
      if boot.alpha == 0 { hide() }
    }
  }

  // MARK: Loading and showing

  private func frameworkURL(_ embedded: Game.Embedded) -> URL {
    Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(embedded.framework).framework")
  }

  private func gameClass(of game: Game, _ embedded: Game.Embedded) throws -> PadHubGame.Type {
    if let type = classes[game.id] { return type }
    guard let bundle = Bundle(url: frameworkURL(embedded)) else {
      throw HostError("\(embedded.framework) is not part of this build.")
    }
    try bundle.loadAndReturnError()
    guard let principal = bundle.principalClass as? NSObject.Type,
      principal.instancesRespond(to: #selector(PadHubGame.resume))
    else {
      throw HostError("\(embedded.framework) has no PadHub game in it.")
    }
    // The framework's class adopts PadHubGame (its principal class).
    let type = unsafeBitCast(principal, to: PadHubGame.Type.self)
    classes[game.id] = type
    return type
  }

  private func hubWindow() -> UIWindow? {
    if let menuWindow { return menuWindow }
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    return scene?.windows.first { $0 !== window && $0 !== gameMenuWindow }
  }

  private func topViewController(of window: UIWindow?) -> UIViewController? {
    var top = window?.rootViewController
    while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
    return top
  }

  private func show(_ viewController: UIViewController) {
    guard
      let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState != .unattached })
    else { return }
    if menuWindow == nil {
      menuWindow = scene.windows.first { $0.isKeyWindow } ?? scene.windows.first
    }
    let window = self.window ?? UIWindow(windowScene: scene)
    self.window = window
    if window.rootViewController !== viewController {
      window.rootViewController = viewController
    }
    window.alpha = 0
    window.makeKeyAndVisible()
    viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
    UIView.animate(withDuration: 0.35) {
      window.alpha = 1
    } completion: { _ in
      // The menu stops drawing while the game is in front.
      if self.inFront { self.menuWindow?.isHidden = true }
    }
  }

  private struct HostError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}

/// PadHub's menu over a game turns with the game, never on its own.
private final class GameMenuController: UIHostingController<AnyView> {
  weak var game: UIViewController?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
  }

  override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
    game?.supportedInterfaceOrientations ?? .all
  }

  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
}
