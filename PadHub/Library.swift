import SwiftUI
import UIKit

/// The games PadHub shows, in the player's order, with their covers.
final class Library: ObservableObject {
  @Published private(set) var games: [Game] = []
  @Published private(set) var hidden: Set<String> = []
  @Published private(set) var installed: Set<String> = []
  @Published private(set) var covers: [String: UIImage] = [:]

  private let defaults = UserDefaults.standard
  private static let gamesKey = "PadHubGames"
  private static let hiddenKey = "PadHubHidden"

  init() {
    load()
    refreshInstalled()
  }

  var visibleGames: [Game] { games.filter { !hidden.contains($0.id) } }

  /// Built-in games are shown once installed; added games always are.
  func refreshInstalled() {
    var found = Set<String>()
    for game in games where game.url.map(UIApplication.shared.canOpenURL) ?? false {
      found.insert(game.id)
    }
    installed = found
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
