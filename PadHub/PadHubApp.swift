import SwiftUI

@main
struct PadHubApp: App {
  @StateObject private var library = Library()
  @StateObject private var controllers = Controllers()
  @StateObject private var host = GameHost()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      HubView(library: library, controllers: controllers, host: host)
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onAppear {
          Log.write("launch \(ProcessInfo.processInfo.arguments.dropFirst().joined(separator: " "))")
          host.willShowGame = { [controllers] in controllers.release() }
          host.didReturnToMenu = { [controllers] in controllers.claim() }
          host.didImportDisc = { [library] in library.refreshInstalled() }
          controllers.start()
          DiscImports.prepare()
          library.refreshInstalled()
          if ProcessInfo.processInfo.arguments.contains("-padhubSelfTest") {
            runSelfTest()
          } else {
            // A restart for another game (a Switch game cannot end) opens it now.
            openRequestedGame(GameHost.takeGameToOpenAtLaunch() ?? Self.launchArgumentGame)
          }
        }
        // padhub://open/<game>, e.g. padhub://open/sunpad from a Shortcut.
        .onOpenURL { url in
          guard url.host() == "open" else { return }
          openRequestedGame(url.lastPathComponent)
        }
        // A game app may have been installed or removed while PadHub was away.
        .onChange(of: scenePhase) { _, phase in
          Log.write("scene \(phase)")
          if phase == .active { library.refreshInstalled() }
        }
    }
  }

  /// `-padhubOpen <game>` opens a built-in game at launch: with a game's own
  /// import arguments (-sunpadImportTest, -meleepadImportTest), it imports a
  /// disc from Xcode or devicectl without touching the phone.
  private static var launchArgumentGame: String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-padhubOpen"), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  /// `-padhubSelfTest`: opens each built-in game, goes back to the menu, and
  /// switches between them, so a Mac can check that the cores share the
  /// process (PadHub.log and the games' logs tell how it went).
  private func runSelfTest() {
    let built = library.games.filter { $0.embedded != nil && library.isInstalled($0) }
    var steps: [(TimeInterval, () -> Void)] = []
    for game in built + built.prefix(1) {
      steps.append((2, { host.open(game) }))
      steps.append((30, { host.returnToMenu() }))
    }
    var delay: TimeInterval = 0
    for (index, step) in steps.enumerated() {
      delay += step.0
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        Log.write("self-test step \(index + 1)/\(steps.count)")
        step.1()
        if index == steps.count - 1 { Log.write("self-test done") }
      }
    }
  }

  private func openRequestedGame(_ id: String?) {
    guard let id, let game = library.games.first(where: { $0.id == id }), game.embedded != nil,
      library.isInstalled(game)
    else { return }
    // Let the menu's window settle first.
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      if host.current?.id != game.id || !host.inFront { host.open(game) }
    }
  }
}
