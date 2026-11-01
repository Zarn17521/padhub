import SwiftUI
import UIKit

/// Runs the games built into PadHub. Each core is a framework (SunPadGame,
/// MeleePadGame) loaded the first time its game opens. A game shows in a
/// window above the menu and waits there, paused, while the player is back in
/// the menu; starting another game ends it first. One game runs at a time.
@MainActor
final class GameHost: ObservableObject {
  /// The game in front, or paused behind the menu.
  @Published private(set) var current: Game?
  @Published private(set) var inFront = false
  @Published var failure: String?

  /// The menu gives its controllers to the game, and takes them back.
  var willShowGame: (() -> Void)?
  var didReturnToMenu: (() -> Void)?
  var didImportDisc: (() -> Void)?

  private var loaded: [String: PadHubGame] = [:]
  private var window: UIWindow?
  private weak var menuWindow: UIWindow?

  /// Opens a built-in game, or brings back the one paused behind the menu.
  /// Another game in progress ends first, as when quitting it.
  func open(_ game: Game) {
    guard let embedded = game.embedded else { return }
    if let current, current.id != game.id {
      Log.write("stop \(current.id) to start \(game.id)")
      loaded[current.id]?.stop()
      self.current = nil
    }
    let instance: PadHubGame
    if let existing = loaded[game.id] {
      instance = existing
    } else {
      do {
        instance = try load(embedded)
        Log.write("loaded \(embedded.framework)")
      } catch {
        Log.write("could not load \(embedded.framework): \(error.localizedDescription)")
        failure = error.localizedDescription
        return
      }
      loaded[game.id] = instance
    }
    Log.write("open \(game.id)")
    willShowGame?()
    show(instance.viewController)
    instance.resume()
    current = game
    inFront = true
    if let disc = DiscImports.disc(for: game), let claimed = DiscImports.claim(disc) {
      Log.write("import \(disc.lastPathComponent) into \(game.id)")
      instance.importDisc?(at: claimed)
      didImportDisc?()
    }
  }

  /// The game's menu or the controller's HOME button: back to PadHub, with
  /// the game paused where it was.
  func returnToMenu() {
    guard inFront, let current, let instance = loaded[current.id] else { return }
    Log.write("back to the menu from \(current.id)")
    instance.suspend()
    inFront = false
    menuWindow?.isHidden = false
    UIView.animate(withDuration: 0.3) {
      self.window?.alpha = 0
    } completion: { _ in
      guard !self.inFront else { return }
      self.window?.isHidden = true
      self.menuWindow?.makeKey()
    }
    didReturnToMenu?()
  }

  /// Ends the game paused behind the menu.
  func closeCurrent() {
    guard !inFront, let current else { return }
    Log.write("close \(current.id)")
    loaded[current.id]?.stop()
    self.current = nil
  }

  private func load(_ embedded: Game.Embedded) throws -> PadHubGame {
    let url = Bundle.main.bundleURL.appendingPathComponent("Frameworks/\(embedded.framework).framework")
    guard let bundle = Bundle(url: url) else {
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
    return type.init(exitHandler: { [weak self] in self?.returnToMenu() })
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
