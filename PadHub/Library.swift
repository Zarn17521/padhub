import SwiftUI
import UIKit

/// The games PadHub shows, in the player's order, with their covers.
final class Library: ObservableObject {
  @Published private(set) var games: [Game] = []
  @Published private(set) var hidden: Set<String> = []
  @Published private(set) var installed: Set<String> = []
  /// Games with a disc waiting in the Import folder.
  @Published private(set) var discsToImport: Set<String> = []
  /// The player's own pictures, which win over the box art.
  @Published private(set) var covers: [String: UIImage] = [:]
  @Published private(set) var boxArt: [String: UIImage] = [:]

  private let defaults = UserDefaults.standard
  private static let gamesKey = "PadHubGames"
  private static let hiddenKey = "PadHubHidden"

  init() {
    load()
    refreshInstalled()
    loadBoxArt()
  }

  var visibleGames: [Game] { games.filter { !hidden.contains($0.id) } }

  func cover(for game: Game) -> UIImage? { covers[game.id] ?? boxArt[game.id] }

  /// A built-in game is installed when this build carries its core and its
  /// module; a game app, when it is on the device. Added games always are.
  func refreshInstalled() {
    var found = Set<String>()
    for game in games {
      if let embedded = game.embedded {
        let app = Bundle.main.bundleURL
        let framework = app.appendingPathComponent("Frameworks/\(embedded.framework).framework")
        let module = embedded.module.map { app.appendingPathComponent($0).path }
        if FileManager.default.fileExists(atPath: framework.path),
          module.map(FileManager.default.fileExists(atPath:)) ?? true
        {
          found.insert(game.id)
        }
      } else if game.url.map(UIApplication.shared.canOpenURL) ?? false {
        found.insert(game.id)
      }
    }
    installed = found
    discsToImport = Set(games.filter { DiscImports.disc(for: $0) != nil }.map(\.id))
  }

  func isInstalled(_ game: Game) -> Bool { game.isCustom || installed.contains(game.id) }

  func setHidden(_ isHidden: Bool, for game: Game) {
    if isHidden { hidden.insert(game.id) } else { hidden.remove(game.id) }
    save()
  }

  func move(from source: IndexSet, to destination: Int) {
    games.move(fromOffsets: source, toOffset: destination)
    save()
  }

  func add(title: String, platform: Platform, scheme: String) {
    let cleaned = scheme.replacingOccurrences(of: "://", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let palette = Game.customPalettes[games.count % Game.customPalettes.count]
    games.append(
      Game(
        id: "custom-\(UUID().uuidString)", title: title, platform: platform, scheme: cleaned,
        colors: palette, symbol: platform.symbol, isCustom: true))
    save()
  }

  func remove(_ game: Game) {
    guard game.isCustom else { return }
    games.removeAll { $0.id == game.id }
    setCover(nil, for: game)
    save()
  }

  // MARK: Covers

  func setCover(_ image: UIImage?, for game: Game) {
    let url = Self.coverURL(for: game.id)
    if let image, let data = image.jpegData(compressionQuality: 0.85) {
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? data.write(to: url, options: .atomic)
      covers[game.id] = image
    } else {
      try? FileManager.default.removeItem(at: url)
      covers[game.id] = nil
    }
  }

  private static func coverURL(for id: String) -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return documents.appendingPathComponent("Covers/\(id).jpg")
  }

  // MARK: Box art, downloaded once and kept

  private static func boxArtURL(for id: String) -> URL {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return support.appendingPathComponent("BoxArt/\(id).jpg")
  }

  private func loadBoxArt() {
    for game in games where !game.boxArtSources.isEmpty {
      if let image = UIImage(contentsOfFile: Self.boxArtURL(for: game.id).path) {
        boxArt[game.id] = image
      } else {
        Task { await downloadBoxArt(for: game) }
      }
    }
  }

  @MainActor
  private func downloadBoxArt(for game: Game) async {
    for source in game.boxArtSources {
      guard let download = try? await URLSession.shared.data(from: source.url),
        (download.1 as? HTTPURLResponse)?.statusCode == 200,
        let image = UIImage(data: download.0),
        let cover = source.isFullSleeve ? Self.front(ofSleeve: image) : image,
        let jpeg = cover.jpegData(compressionQuality: 0.9)
      else { continue }
      let url = Self.boxArtURL(for: game.id)
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? jpeg.write(to: url, options: .atomic)
      withAnimation(.easeInOut(duration: 0.5)) { boxArt[game.id] = cover }
      return
    }
  }

  /// A GameCube sleeve is back, spine and front side by side: the front is its
  /// right end, as tall as the sleeve and 0.71 times as wide as tall.
  private static func front(ofSleeve sleeve: UIImage) -> UIImage? {
    guard let image = sleeve.cgImage else { return nil }
    let width = Int((Double(image.height) * 0.71).rounded())
    let rect = CGRect(x: image.width - width, y: 0, width: width, height: image.height)
    return image.cropping(to: rect).map { UIImage(cgImage: $0) }
  }

  // MARK: Storage

  private func load() {
    var stored: [Game] = []
    if let data = defaults.data(forKey: Self.gamesKey),
      let decoded = try? JSONDecoder().decode([Game].self, from: data)
    {
      stored = decoded
    }
    // Built-in games keep their latest definition; new ones join at the end.
    var merged = stored.map { game in Game.catalog.first { $0.id == game.id } ?? game }
    for game in Game.catalog where !merged.contains(where: { $0.id == game.id }) {
      merged.append(game)
    }
    games = merged
    hidden = Set(defaults.stringArray(forKey: Self.hiddenKey) ?? [])
    for game in games {
      if let image = UIImage(contentsOfFile: Self.coverURL(for: game.id).path) {
        covers[game.id] = image
      }
    }
  }

  private func save() {
    if let data = try? JSONEncoder().encode(games) { defaults.set(data, forKey: Self.gamesKey) }
    defaults.set(Array(hidden), forKey: Self.hiddenKey)
  }
}
