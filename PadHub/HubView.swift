import SwiftUI

struct HubView: View {
  @ObservedObject var library: Library
  @ObservedObject var controllers: Controllers

  @State private var selection: String?
  @State private var launching: Game?
  @State private var showingSettings = false
  @State private var notInstalled: Game?

  private var games: [Game] { library.visibleGames }

  private var selectedGame: Game? {
    games.first { $0.id == selection } ?? games.first
  }

  var body: some View {
    ZStack {
      AnimatedBackground(palette: selectedGame?.palette ?? [.indigo, .purple, .blue])
        .id(selectedGame?.id)
        .transition(.opacity)

      VStack(spacing: 0) {
        header
        Spacer(minLength: 12)
        carousel
        details
        Spacer(minLength: 12)
        hints
      }

      if let launching {
        LaunchOverlay(game: launching)
          .transition(.opacity)
      }
    }
    .animation(.easeInOut(duration: 0.7), value: selectedGame?.id)
    .sheet(isPresented: $showingSettings) {
      SettingsView(library: library, controllers: controllers)
    }
    .alert(item: $notInstalled) { game in
      Alert(
        title: Text("\(game.title) is not installed"),
        message: Text("Build and install its app from your Mac, then come back: it shows up here on its own."),
        dismissButton: .default(Text("OK")))
    }
    .onAppear {
      if selection == nil { selection = games.first?.id }
      controllers.onCommand = handle
    }
  }

  // MARK: Parts

  private var header: some View {
    HStack {
      HStack(spacing: 10) {
        Image("Logo")
          .resizable()
          .scaledToFit()
          .frame(height: 44)
          .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        Text("PadHub")
          .font(.system(size: 34, weight: .black, design: .rounded))
          .foregroundStyle(.white)
      }
      Spacer()
      Label(controllers.statusText, systemImage: controllers.isConnected ? "gamecontroller.fill" : "dot.radiowaves.left.and.right")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(controllers.isConnected ? .white : .white.opacity(0.7))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .symbolEffect(.pulse, isActive: !controllers.isConnected)
      Button {
        showingSettings = true
      } label: {
        Image(systemName: "slider.horizontal.3")
          .font(.title3.weight(.semibold))
          .padding(10)
          .background(.ultraThinMaterial, in: Circle())
      }
      .tint(.white)
    }
    .padding(.horizontal, 24)
    .padding(.top, 16)
  }

  private var carousel: some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 28) {
        ForEach(games) { game in
          GameCard(
            game: game, cover: library.covers[game.id], installed: library.isInstalled(game),
            selected: game.id == selectedGame?.id
          )
          .id(game.id)
          .onTapGesture {
            if game.id == selectedGame?.id { launch(game) } else { select(game.id) }
          }
          .scrollTransition(.interactive, axis: .horizontal) { content, phase in
            content
              .scaleEffect(phase.isIdentity ? 1 : 0.82)
              .rotation3DEffect(.degrees(phase.value * -28), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
              .opacity(phase.isIdentity ? 1 : 0.55)
              .blur(radius: phase.isIdentity ? 0 : 1.5)
          }
        }
      }
      .scrollTargetLayout()
    }
    .scrollIndicators(.hidden)
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $selection, anchor: .center)
    .safeAreaPadding(.horizontal, 60)
    .contentMargins(.horizontal, 60, for: .scrollContent)
    .frame(height: 400)
    .sensoryFeedback(.selection, trigger: selection)
  }

  private var details: some View {
    VStack(spacing: 6) {
      if let game = selectedGame {
        Text(game.title)
          .font(.title2.weight(.bold))
          .foregroundStyle(.white)
          .contentTransition(.numericText())
        Text(library.isInstalled(game) ? "Ready to play" : "Not installed on this device")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.7))
      } else {
        Text("No games yet")
          .font(.title2.weight(.bold))
        Text("Add one in the settings")
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .padding(.top, 8)
    .animation(.snappy, value: selectedGame?.id)
  }

  private var hints: some View {
    HStack(spacing: 22) {
      hint("A", "Play")
      hint("←→", "Choose")
      hint("START", "Settings")
    }
    .padding(.bottom, 18)
    .opacity(controllers.isConnected ? 1 : 0.45)
  }

  private func hint(_ key: String, _ action: String) -> some View {
    HStack(spacing: 6) {
      Text(key)
        .font(.caption.weight(.black))
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(.white.opacity(0.85), in: Capsule())
        .foregroundStyle(.black)
      Text(action).font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
    }
  }

  // MARK: Actions

  private func handle(_ command: Controllers.Command) {
    if showingSettings {
      if command == .back || command == .menu { showingSettings = false }
      return
    }
    if launching != nil { return }
    switch command {
    case .left: step(-1)
    case .right: step(1)
    case .up, .down: break
    case .confirm: if let game = selectedGame { launch(game) }
    case .back: break
    case .menu: showingSettings = true
    }
  }

  private func step(_ offset: Int) {
    guard !games.isEmpty else { return }
    let index = games.firstIndex { $0.id == selectedGame?.id } ?? 0
    let next = min(max(index + offset, 0), games.count - 1)
    if next != index { select(games[next].id) }
  }

  private func select(_ id: String) {
    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { selection = id }
  }

  private func launch(_ game: Game) {
    guard library.isInstalled(game), let url = game.url else {
      notInstalled = game
      return
    }
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    withAnimation(.easeIn(duration: 0.35)) { launching = game }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
      UIApplication.shared.open(url) { opened in
        if !opened { notInstalled = game }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
          withAnimation(.easeOut(duration: 0.3)) { launching = nil }
        }
      }
    }
  }
}

/// The selected game fills the screen just before its app opens.
private struct LaunchOverlay: View {
  let game: Game
  @State private var grow = false

  var body: some View {
    ZStack {
      RadialGradient(
        colors: [game.palette.first ?? .white, .black], center: .center, startRadius: 10,
        endRadius: grow ? 900 : 60)
      Image(systemName: game.symbol)
        .font(.system(size: 120, weight: .black))
        .foregroundStyle(.white)
        .scaleEffect(grow ? 1.6 : 0.6)
        .opacity(grow ? 0 : 1)
    }
    .ignoresSafeArea()
    .onAppear { withAnimation(.easeIn(duration: 0.5)) { grow = true } }
  }
}
