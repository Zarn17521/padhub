import Foundation

/// Discs waiting in PadHub's Import folder (Documents/Import: the Files app,
/// the Finder, or devicectl from a Mac can put them there). The next time
/// their game opens, PadHub hands each one over, recognized by the game ID at
/// the start of the disc, and the game imports it as its own picker would.
enum DiscImports {
  static var folder: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Import")
  }

  private static var handoff: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("PadHub import")
  }

  /// Makes the folder, so the Files app shows it, and drops discs already
  /// handed over at an earlier launch, or copied by a Mac for a game's own
  /// import argument (-sunpadImportTest).
  static func prepare() {
    let files = FileManager.default
    try? files.createDirectory(at: folder, withIntermediateDirectories: true)
    try? files.removeItem(at: handoff)
    guard !ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("ImportTest") }) else { return }
    let leftovers =
      (try? files.contentsOfDirectory(at: files.temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
    for file in leftovers where ["iso", "gcm"].contains(file.pathExtension.lowercased()) {
      try? files.removeItem(at: file)
    }
  }

  /// A disc for this game, ready to import.
  static func disc(for game: Game) -> URL? {
    guard game.embedded != nil, let id = game.artID else { return nil }
    let files =
      (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    return files.first { ["iso", "gcm"].contains($0.pathExtension.lowercased()) && gameID(of: $0) == id }
  }

  /// Moves the disc out of the Import folder, so it is imported only once.
  static func claim(_ disc: URL) -> URL? {
    let destination = handoff.appendingPathComponent(disc.lastPathComponent)
    do {
      try FileManager.default.createDirectory(at: handoff, withIntermediateDirectories: true)
      try? FileManager.default.removeItem(at: destination)
      try FileManager.default.moveItem(at: disc, to: destination)
      return destination
    } catch {
      return nil
    }
  }

  /// A GameCube or Wii disc starts with its six-character game ID.
  private static func gameID(of url: URL) -> String? {
    guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
    defer { try? handle.close() }
    guard let data = try? handle.read(upToCount: 6), data.count == 6 else { return nil }
    return String(data: data, encoding: .ascii)
  }
}
