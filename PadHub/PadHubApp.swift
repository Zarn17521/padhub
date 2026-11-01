import SwiftUI

@main
struct PadHubApp: App {
  @StateObject private var library = Library()
  @StateObject private var controllers = Controllers()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      HubView(library: library, controllers: controllers)
        .preferredColorScheme(.dark)
        .persistentSystemOverlays(.hidden)
        .onAppear { controllers.start() }
        // A game may have been installed or removed while PadHub was away.
        .onChange(of: scenePhase) { _, phase in
          if phase == .active { library.refreshInstalled() }
        }
    }
  }
}
