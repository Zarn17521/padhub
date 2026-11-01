import SwiftUI

struct HubView: View {
  @ObservedObject var library: Library
  @ObservedObject var controllers: Controllers
  @ObservedObject var host: GameHost

  @State private var selection: String?
  @State private var launching: Game?
  @State private var showingSettings = false
  @State private var notInstalled: Game?
  /// Starting this game ends the one paused behind the menu: asked first.
  @State private var replacing: Game?

  private var games: [Game] { library.visibleGames }

  private var selectedGame: Game? {
    games.first { $0.id == selection } ?? games.first
  }

  var body: some View {
    GeometryReader { proxy in
      hub(HubLayout(size: proxy.size))
    }
  }

  private func hub(_ layout: HubLayout) -> some View {
    ZStack {
      AnimatedBackground(
        palette: selectedGame?.palette ?? [.indigo, .purple, .blue], paused: host.inFront)
        .id(selectedGame?.id)
        .transition(.opacity)

      VStack(spacing: 0) {
        header(layout)
        Spacer(minLength: layout.compact ? 4 : 12)
        carousel(layout)
        details(layout)
        Spacer(minLength: layout.compact ? 4 : 12)
        hints(layout)
      }

      if let replacing, let paused = host.current {
        ReplaceGamePrompt(paused: paused, next: replacing) {
          self.replacing = nil
          launch(replacing, replacingPaused: true)
        } cancel: {
          self.replacing = nil
        }
        .transition(.opacity.combined(with: .scale(scale: 1.05)))
      }

      if let launching {
        LaunchOverlay(game: launching, cover: library.cover(for: launching))
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
        message: Text(
          game.embedded != nil
            ? "This build of PadHub has no module for it: put the module made from your disc in Modules/ and build PadHub again."
            : "Build and install its app from your Mac, then come back: it shows up here on its own."),
        dismissButton: .default(Text("OK")))
    }
    .alert(
      "The game could not start", isPresented: .constant(host.failure != nil),
      presenting: host.failure
    ) { _ in
      Button("OK") { host.failure = nil }
    } message: { failure in
      Text(failure)
    }
    .animation(.easeInOut(duration: 0.25), value: replacing?.id)
    .onAppear {
      if selection == nil { selection = games.first?.id }
      controllers.onCommand = handle
    }
  }

  // MARK: Parts

  private func header(_ layout: HubLayout) -> some View {
    HStack {
      HStack(spacing: 10) {
        Image("Logo")
          .resizable()
          .scaledToFit()
          .frame(height: layout.compact ? 34 : 44)
          .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
        Text("PadHub")
          .font(.system(size: layout.compact ? 26 : 34, weight: .black, design: .rounded))
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
    .padding(.top, layout.compact ? 8 : 16)
  }

  private func carousel(_ layout: HubLayout) -> some View {
    ScrollView(.horizontal) {
      LazyHStack(spacing: 28 * layout.cardScale) {
        ForEach(games) { game in
          card(game, scale: layout.cardScale)
        }
      }
      .scrollTargetLayout()
    }
    .scrollIndicators(.hidden)
    .scrollTargetBehavior(.viewAligned)
    .scrollPosition(id: $selection, anchor: .center)
    // The selected card stops in the middle, the first and last ones too.
    .contentMargins(.horizontal, layout.cardMargin, for: .scrollContent)
    .frame(height: GameCard.size.height * layout.cardScale + 40)
    .sensoryFeedback(.selection, trigger: selection)
  }

  private func card(_ game: Game, scale: CGFloat) -> some View {
    let size = CGSize(width: GameCard.size.width * scale, height: GameCard.size.height * scale)
    return GameCard(
      game: game, cover: library.cover(for: game), installed: library.isInstalled(game),
      selected: game.id == selectedGame?.id, paused: host.current?.id == game.id
    )
    .scaleEffect(scale)
    .frame(width: size.width, height: size.height)
    .id(game.id)
    .onTapGesture {
      if game.id == selectedGame?.id { launch(game) } else { select(game.id) }
    }
    // The centered card stands out; the others turn away and fade.
    .scrollTransition(.interactive.threshold(.centered), axis: .horizontal) { content, phase in
      carouselTilt(content, phase: phase.value)
    }
  }

  private func details(_ layout: HubLayout) -> some View {
    VStack(spacing: layout.compact ? 4 : 6) {
      if let game = selectedGame {
        Text(game.title)
          .font(layout.compact ? .title3.weight(.bold) : .title2.weight(.bold))
          .foregroundStyle(.white)
          .contentTransition(.numericText())
        // On a short screen the Close button sits beside the status.
        let closeButton = host.current?.id == game.id && !host.inFront
        if layout.compact {
          HStack(spacing: 10) {
            statusText(of: game)
            if closeButton { closeGameButton }
          }
        } else {
          statusText(of: game)
          if closeButton { closeGameButton }
        }
      } else {
        Text("No games yet")
          .font(.title2.weight(.bold))
        Text("Add one in the settings")
          .foregroundStyle(.white.opacity(0.7))
      }
    }
    .padding(.top, layout.compact ? 2 : 8)
    .animation(.snappy, value: selectedGame?.id)
  }

  private func statusText(of game: Game) -> some View {
    Text(status(of: game))
      .font(.subheadline)
      .foregroundStyle(.white.opacity(0.7))
  }

  private var closeGameButton: some View {
    Button {
      withAnimation(.snappy) { host.closeCurrent() }
    } label: {
      Label("Close game", systemImage: "xmark")
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
    }
    .tint(.white)
    .transition(.opacity.combined(with: .scale(scale: 0.9)))
  }

  private func hints(_ layout: HubLayout) -> some View {
    HStack(spacing: 22) {
      hint("A", selectedGame.map { host.current?.id == $0.id } == true ? "Resume" : "Play")
      hint("←→", "Choose")
      if let paused = host.current, selectedGame?.id != paused.id { hint("HOME", "Back to game") }
      hint("START", "Settings")
    }
    .padding(.bottom, layout.compact ? 10 : 18)
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

  private func status(of game: Game) -> String {
    if host.current?.id == game.id { return "Paused — press A to pick up where you left off" }
    if !library.isInstalled(game) { return "Not installed on this device" }
    if library.discsToImport.contains(game.id) { return "Your disc is in the Import folder: it imports when you start" }
    return game.embedded != nil ? "Ready to play" : "Opens its own app"
  }

  // MARK: Actions

  private func handle(_ command: Controllers.Command) {
    if host.inFront { return }
    if showingSettings {
      if command == .back || command == .menu { showingSettings = false }
      return
    }
    if let replacing {
      if command == .confirm {
        self.replacing = nil
        launch(replacing, replacingPaused: true)
      } else if command == .back || command == .home {
        self.replacing = nil
      }
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
    case .home: if let paused = host.current { launch(paused) }
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

  private func launch(_ game: Game, replacingPaused: Bool = false) {
    guard library.isInstalled(game) else {
      notInstalled = game
      return
    }
    if game.embedded != nil, let paused = host.current, paused.id != game.id, !replacingPaused {
      replacing = game
      return
    }
    select(game.id)
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    // Back to a paused game: no need for the whole show.
    let resuming = host.current?.id == game.id
    withAnimation(.easeIn(duration: resuming ? 0.2 : 0.35)) { launching = game }
    DispatchQueue.main.asyncAfter(deadline: .now() + (resuming ? 0.2 : 0.55)) {
      if game.embedded != nil {
        host.open(game)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { launching = nil }
      } else if let url = game.url {
        UIApplication.shared.open(url) { opened in
          if !opened { notInstalled = game }
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.3)) { launching = nil }
          }
        }
      }
    }
  }
}

/// Starting another game ends the paused one, as on a console.
private struct ReplaceGamePrompt: View {
  let paused: Game
  let next: Game
  let confirm: () -> Void
  let cancel: () -> Void

  var body: some View {
    ZStack {
      Color.black.opacity(0.55).ignoresSafeArea()
        .onTapGesture(perform: cancel)
      VStack(spacing: 14) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 40, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
        Text("Close \(paused.title)?")
          .font(.title2.weight(.bold))
          .foregroundStyle(.white)
        Text("\(next.title) starts once it is closed. Progress you have not saved in the game is lost.")
          .font(.subheadline)
          .foregroundStyle(.white.opacity(0.75))
          .multilineTextAlignment(.center)
          .frame(maxWidth: 420)
        HStack(spacing: 14) {
          Button(action: cancel) {
            Label("Cancel", systemImage: "b.circle.fill")
              .frame(minWidth: 150)
          }
          .buttonStyle(.bordered)
          Button(action: confirm) {
            Label("Close and play", systemImage: "a.circle.fill")
              .frame(minWidth: 150)
          }
          .buttonStyle(.borderedProminent)
        }
        .controlSize(.large)
        .tint(.white)
        .foregroundStyle(.black)
        .padding(.top, 6)
      }
      .padding(28)
      .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
    }
  }
}

/// The selected game fills the screen just before it starts.
private struct LaunchOverlay: View {
  let game: Game
  let cover: UIImage?
  @State private var grow = false

  var body: some View {
    ZStack {
      RadialGradient(
        colors: [game.palette.first ?? .white, .black], center: .center, startRadius: 10,
        endRadius: grow ? 900 : 60)
      Group {
        if let cover {
          Image(uiImage: cover)
            .resizable()
            .scaledToFit()
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        } else {
          Image(systemName: game.symbol)
            .font(.system(size: 120, weight: .black))
            .foregroundStyle(.white)
        }
      }
      .scaleEffect(grow ? 1.6 : 0.8)
      .opacity(grow ? 0 : 1)
    }
    .ignoresSafeArea()
    .onAppear { withAnimation(.easeIn(duration: 0.5)) { grow = true } }
  }
}

/// The hub fits any screen: on a short one (a phone in landscape) the cards
/// shrink so the header, the selected game's details and the hints all show.
private struct HubLayout {
  let compact: Bool
  let cardScale: CGFloat
  /// Room on each side of the cards, so the selected one can sit centered.
  let cardMargin: CGFloat

  init(size: CGSize) {
    compact = size.height < 600
    // What the header, the details and the hints take around the cards.
    let around: CGFloat = compact ? 175 : 290
    cardScale = min(1, max(0.5, (size.height - around) / 380))
    cardMargin = max(0, (size.width - GameCard.size.width * cardScale) / 2)
  }
}

/// A card away from the middle of the carousel: smaller, turned, faded.
/// `phase` runs from -1 (left) through 0 (centered) to 1 (right).
private func carouselTilt(_ effect: EmptyVisualEffect, phase: Double) -> some VisualEffect {
  let away = min(abs(phase), 1)
  let scale = CGFloat(1 - 0.18 * away)
  let opacity = 1 - 0.45 * away
  let blur = CGFloat(1.5 * away)
  let turn = Angle.degrees(phase * -28)
  return effect
    .scaleEffect(scale)
    .rotation3DEffect(turn, axis: (x: 0, y: 1, z: 0), perspective: 0.6)
    .opacity(opacity)
    .blur(radius: blur)
}
