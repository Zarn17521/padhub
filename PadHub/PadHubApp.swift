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
          host.gameMenu.controllers = controllers
          host.makeGameMenu = { [host, controllers, library] in
            AnyView(GameMenuView(model: host.gameMenu, controllers: controllers, library: library))
          }
          host.makeBootScreen = { [library] game in
            AnyView(DiscBootView(game: game, disc: library.disc(for: game), cover: library.cover(for: game)))
          }
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
  /// process (PadHub.log and the games' logs tell how it went). It then cycles
  /// the games that stop in-process (the Switch games): it starts and quits
  /// each from the menu, freeing its memory, and starts one of them again, so
  /// a device run checks stop and restart from the logs. Games that keep
  /// running (Wind Waker) are left out of that round: quitting one restarts
  /// the app, which would cut the test short.
  private func runSelfTest() {
    // `-padhubSelfTestGames wonder,sunpad` keeps the test to those games, in that order.
    let arguments = ProcessInfo.processInfo.arguments
    let only = arguments.firstIndex(of: "-padhubSelfTestGames").flatMap {
      $0 + 1 < arguments.count ? arguments[$0 + 1].split(separator: ",").map(String.init) : nil
    }
    let installed = library.games.filter { $0.embedded != nil && library.isInstalled($0) }
    let built = only.map { ids in ids.compactMap { id in installed.first { $0.id == id } } } ?? installed
    let stoppable = built.filter { !$0.keepsRunning }
    var steps: [(TimeInterval, () -> Void)] = []
    for game in built + built.prefix(1) {
      steps.append((2, { host.open(game) }))
      steps.append((30, { host.returnToMenu() }))
    }
    // Then: start each stoppable game and quit it (which stops it and frees its memory), and
    // finally start the first one again, to prove a game restarts after it has been stopped.
    for game in stoppable {
      steps.append((2, { host.open(game) }))
      steps.append((30, { host.showGameMenu() }))
      steps.append((1, { host.quitFromGameMenu() }))
    }
    if let again = stoppable.first {
      steps.append((2, { host.open(again) }))
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
      showGameMenuForTest()
    }
  }

  /// `-padhubGameMenuAfter <seconds> [-padhubGameMenuPage controllers]`: brings
  /// up PadHub's menu over the game opened at launch, for screenshots taken
  /// from a Mac.
  private func showGameMenuForTest() {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-padhubGameMenuAfter"), index + 1 < arguments.count,
      let seconds = Double(arguments[index + 1])
    else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
      host.showGameMenu()
      if let page = arguments.firstIndex(of: "-padhubGameMenuPage"), page + 1 < arguments.count,
        arguments[page + 1] == "controllers"
      {
        host.gameMenu.activate(.controllers)
      }
    }
  }
}
