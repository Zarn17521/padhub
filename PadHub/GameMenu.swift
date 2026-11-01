import SwiftUI

/// PadHub's menu over a game: what it shows and which row is chosen, by touch
/// or with any controller (Controllers' commands, which HubView passes on
/// while the menu is up). Main thread only.
@MainActor
final class GameMenuModel: ObservableObject {
  enum Page { case main, controllers, confirmQuit }

  enum Row: Hashable {
    case resume, controllers, settings, hub, quit
    /// A controller in the list (Controllers.Connected.id): A rumbles it.
    case controller(String)
    case mapping, forget, back
    case confirmQuit, cancelQuit
  }

  @Published private(set) var page: Page = .main
  @Published var selection: Row = .resume
  @Published private(set) var game: Game?
  @Published private(set) var hasSettings = false
  @Published private(set) var hasMapping = false
  /// Quitting this game closes PadHub (a game that cannot end).
  @Published private(set) var quitRestarts = false

  weak var host: GameHost?
  weak var controllers: Controllers?

  func prepare(for game: Game, hasSettings: Bool, hasMapping: Bool, quitRestarts: Bool) {
    self.game = game
    self.hasSettings = hasSettings
    self.hasMapping = hasMapping
    self.quitRestarts = quitRestarts
    page = .main
    selection = .resume
  }

  func rows(of page: Page) -> [Row] {
    switch page {
    case .main:
      return [.resume, .controllers] + (hasSettings ? [.settings] : []) + [.hub, .quit]
    case .controllers:
      let list = controllers?.connected.map { Row.controller($0.id) } ?? []
      let forget = controllers?.hasRememberedNSOControllers == true ? [Row.forget] : []
      return list + (hasMapping ? [.mapping] : []) + forget + [.back]
    case .confirmQuit:
      return [.confirmQuit, .cancelQuit]
    }
  }

  func handle(_ command: Controllers.Command) {
    if let host, host.showingSettings {
      if command == .back || command == .home { host.closeSettings() }
      return
    }
    switch command {
    case .up: move(-1)
    case .down: move(1)
    case .left, .right: break
    case .confirm: activate(selection)
    case .option:
      if case .controller(let id) = selection { disconnect(id) }
    case .back: back()
    case .menu: host?.resumeFromGameMenu()
    case .home: host?.returnToMenu()
    }
  }

  func activate(_ row: Row) {
    selection = row
    switch row {
    case .resume: host?.resumeFromGameMenu()
    case .controllers: show(.controllers)
    case .settings: if let game { host?.showSettings(of: game) }
    case .hub: host?.returnToMenu()
    case .quit: show(.confirmQuit)
    case .controller(let id): identify(id)
    case .mapping: host?.showControllerMappingFromGameMenu()
    case .forget: controllers?.forgetNSOControllers()
    case .back: show(.main, selecting: .controllers)
    case .confirmQuit: host?.quitFromGameMenu()
    case .cancelQuit: show(.main, selecting: .quit)
    }
  }

  func back() {
    switch page {
    case .main: host?.resumeFromGameMenu()
    case .controllers: show(.main, selecting: .controllers)
    case .confirmQuit: show(.main, selecting: .quit)
    }
  }

  func identify(_ id: String) {
    if let controller = controllers?.connected.first(where: { $0.id == id }) { controllers?.identify(controller) }
  }

  func disconnect(_ id: String) {
    if let controller = controllers?.connected.first(where: { $0.id == id }) { controllers?.disconnect(controller) }
  }

  private func show(_ page: Page, selecting row: Row? = nil) {
    withAnimation(.snappy(duration: 0.25)) {
      self.page = page
      selection = row ?? rows(of: page).first ?? .back
    }
  }

  private func move(_ offset: Int) {
    let rows = rows(of: page)
    guard !rows.isEmpty else { return }
    let index = rows.firstIndex(of: selection) ?? 0
    let next = min(max(index + offset, 0), rows.count - 1)
    if rows.firstIndex(of: selection) == nil || next != index {
      selection = rows[next]
      UISelectionFeedbackGenerator().selectionChanged()
    }
  }
}

/// The menu itself: a panel over the paused game.
struct GameMenuView: View {
  @ObservedObject var model: GameMenuModel
  @ObservedObject var controllers: Controllers
  @ObservedObject var library: Library

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Color.black.opacity(0.5).ignoresSafeArea()
          .onTapGesture { model.back() }
        VStack(spacing: 0) {
          header
          Divider().overlay(.white.opacity(0.15))
          ScrollViewReader { scroll in
            ScrollView {
              VStack(spacing: 4) { rows }
                .padding(10)
            }
            .scrollBounceBehavior(.basedOnSize)
            // As tall as the rows, short of the screen's height, where they scroll.
            .frame(height: min(rowsHeight, max(120, proxy.size.height - 150)))
            .onChange(of: model.selection) { _, row in
              withAnimation(.snappy(duration: 0.2)) { scroll.scrollTo(row) }
            }
          }
          Divider().overlay(.white.opacity(0.15))
          footer
        }
        .frame(maxWidth: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
        .padding(.horizontal, 24)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .preferredColorScheme(.dark)
  }

  /// The rows' height without scrolling.
  private var rowsHeight: CGFloat {
    let rows = model.rows(of: model.page)
    let heights = rows.map { row -> CGFloat in
      if case .controller = row { return 52 }
      return 46
    }
    let empty: CGFloat = model.page == .controllers && controllers.connected.isEmpty ? 70 : 0
    return heights.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * 4 + 20 + empty
  }

  private var header: some View {
    HStack(spacing: 12) {
      if let game = model.game, let cover = library.cover(for: game) {
        Image(uiImage: cover)
          .resizable()
          .scaledToFill()
          .frame(width: 34, height: 48)
          .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      } else {
        Image(systemName: model.game?.symbol ?? "gamecontroller.fill")
          .font(.title2)
          .frame(width: 34)
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.headline)
        Text(subtitle).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Image("Logo")
        .resizable()
        .scaledToFit()
        .frame(height: 26)
        .opacity(0.9)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
  }

  private var title: String {
    switch model.page {
    case .main: model.game?.title ?? "Game"
    case .controllers: "Controllers"
    case .confirmQuit: "Quit \(model.game?.title ?? "the game")?"
    }
  }

  private var subtitle: String {
    switch model.page {
    case .main: "Paused"
    case .controllers:
      controllers.scanning
        ? "Press SYNC on an NSO controller to pair it"
        : controllers.bluetoothOn ? "\(controllers.connected.count) connected" : "Bluetooth is off"
    case .confirmQuit:
      model.quitRestarts
        ? "PadHub closes to end this game. Progress you have not saved is lost."
        : "Progress you have not saved in the game is lost."
    }
  }

  @ViewBuilder private var rows: some View {
    ForEach(model.rows(of: model.page), id: \.self) { row in
      switch row {
      case .controller(let id):
        if let controller = controllers.connected.first(where: { $0.id == id }) {
          controllerRow(controller, selected: model.selection == row).id(row)
        }
      default:
        menuRow(row, selected: model.selection == row).id(row)
      }
    }
    if model.page == .controllers && controllers.connected.isEmpty {
      Text(controllers.bluetoothOn ? "No controller yet. Press SYNC on an NSO GameCube controller, or pair another one in iOS's Bluetooth settings." : "Turn Bluetooth on to use a wireless controller.")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(12)
    }
  }

  private func menuRow(_ row: GameMenuModel.Row, selected: Bool) -> some View {
    let (label, symbol, detail) = describe(row)
    let destructive = row == .quit || row == .confirmQuit || row == .forget
    return Button {
      model.activate(row)
    } label: {
      HStack(spacing: 14) {
        Image(systemName: symbol)
          .font(.body.weight(.semibold))
          .frame(width: 26)
          .foregroundStyle(destructive ? .red : .white)
        Text(label).font(.body.weight(.semibold))
        Spacer()
        if let detail {
          Text(detail).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 14)
      .frame(height: 46)
      .background(selected ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
      .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .buttonStyle(.plain)
  }

  private func controllerRow(_ controller: Controllers.Connected, selected: Bool) -> some View {
    HStack(spacing: 14) {
      ZStack {
        Image(systemName: "gamecontroller.fill").font(.body.weight(.semibold))
        if let player = controller.player {
          Text("\(player)")
            .font(.system(size: 10, weight: .black))
            .foregroundStyle(.black)
            .frame(width: 15, height: 15)
            .background(.white, in: Circle())
            .offset(x: 12, y: -9)
        }
      }
      .frame(width: 26)
      VStack(alignment: .leading, spacing: 1) {
        Text(controller.name).font(.body.weight(.semibold))
        Text([controller.player.map { "Player \($0)" }, controller.detail].compactMap { $0 }.joined(separator: " · "))
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        controllers.identify(controller)
      } label: {
        Image(systemName: "waveform").padding(8)
      }
      .accessibilityLabel("Rumble")
      if controller.kind == .nso {
        Button {
          controllers.disconnect(controller)
        } label: {
          Image(systemName: "xmark.circle").padding(8)
        }
        .accessibilityLabel("Disconnect")
      }
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 14)
    .frame(height: 52)
    .background(selected ? .white.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .onTapGesture { model.selection = .controller(controller.id) }
  }

  private func describe(_ row: GameMenuModel.Row) -> (String, String, String?) {
    switch row {
    case .resume: ("Resume", "play.fill", "B")
    case .controllers: ("Controllers", "gamecontroller.fill", controllers.connected.isEmpty ? nil : "\(controllers.connected.count)")
    case .settings: ("Game settings", "slider.horizontal.3", nil)
    case .hub: ("PadHub", "house.fill", "HOME")
    case .quit: ("Quit game", "xmark.circle.fill", nil)
    case .controller: ("", "gamecontroller.fill", nil)
    case .mapping: ("Button mapping", "arrow.left.arrow.right", nil)
    case .forget: ("Forget NSO controllers", "trash", nil)
    case .back: ("Back", "chevron.left", "B")
    case .confirmQuit: (model.quitRestarts ? "Quit and close PadHub" : "Quit", "xmark.circle.fill", nil)
    case .cancelQuit: ("Cancel", "arrow.uturn.backward", "B")
    }
  }

  private var footer: some View {
    HStack(spacing: 16) {
      hint("A", model.page == .controllers ? "Select · rumble" : "Select")
      if case .controller(let id) = model.selection,
        controllers.connected.first(where: { $0.id == id })?.kind == .nso
      {
        hint("Y", "Disconnect")
      }
      hint("B", model.page == .main ? "Resume" : "Back")
      hint("HOME", "PadHub")
    }
    .padding(.vertical, 10)
    .opacity(controllers.isConnected ? 1 : 0.5)
  }

  private func hint(_ key: String, _ action: String) -> some View {
    HStack(spacing: 5) {
      Text(key)
        .font(.system(size: 10, weight: .black))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(.white.opacity(0.85), in: Capsule())
        .foregroundStyle(.black)
      Text(action).font(.caption2.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
    }
  }
}
