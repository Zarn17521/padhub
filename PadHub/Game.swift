import SwiftUI

enum Platform: String, Codable, CaseIterable, Identifiable {
  case nintendoSwitch, gameCube, wii, other

  var id: String { rawValue }

  var label: String {
    switch self {
    case .nintendoSwitch: "Switch"
    case .gameCube: "GameCube"
    case .wii: "Wii"
    case .other: "Other"
    }
  }

  var symbol: String {
    switch self {
    case .nintendoSwitch: "gamecontroller.fill"
    case .gameCube: "cube.fill"
    case .wii: "wand.and.rays"
    case .other: "square.grid.2x2.fill"
    }
  }
}

/// A game in PadHub: built into the app (`embedded`), or an app of its own
/// opened through its URL scheme.
struct Game: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var platform: Platform
  /// Without "://": nxnative registers "nxnative-<title ID>".
  var scheme: String
  /// Hex colors for the card and the background, first one dominant.
  var colors: [String]
  var symbol: String
  var isCustom = false
  /// The game's core inside PadHub, when it is built in.
  var embedded: Embedded?
  /// The game's ID in GameTDB, for its box art.
  var artID: String?

  /// A framework in PadHub.app/Frameworks, and the module made from the
  /// player's own disc that it needs at the top of PadHub.app, if any (a
  /// Switch game's code is in its framework).
  struct Embedded: Codable, Hashable {
    var framework: String
    var module: String?
    /// The game cannot end once started (a Switch game): it waits, paused,
    /// while other games run, and PadHub restarts to start another such game.
    var keepsRunning: Bool?
  }

  var url: URL? { URL(string: "\(scheme)://") }
  var keepsRunning: Bool { embedded?.keepsRunning ?? false }
  var palette: [Color] { colors.map(Color.init(hex:)) }

  /// Where the box art comes from: GameTDB, the database Dolphin uses, first
  /// choice first. A GameCube "full" cover is the whole sleeve (back, spine,
  /// front) in higher resolution than the front alone, so it gets cropped.
  var boxArtSources: [(url: URL, isFullSleeve: Bool)] {
    guard let artID else { return [] }
    let art = "https://art.gametdb.com"
    let sources: [(String, Bool)] =
      switch platform {
      case .gameCube, .wii:
        [("\(art)/wii/coverfullHQ/US/\(artID).png", true), ("\(art)/wii/cover/US/\(artID).png", false)]
      case .nintendoSwitch:
        [("\(art)/switch/coverHQ/EN/\(artID).jpg", false), ("\(art)/switch/coverHQ/US/\(artID).jpg", false)]
      case .other:
        []
      }
    return sources.compactMap { address, isFullSleeve in
      URL(string: address).map { ($0, isFullSleeve) }
    }
  }
}

extension Game {
  /// Games built from this repository's sibling projects.
  static let catalog: [Game] = [
    Game(
      id: "sunpad", title: "Super Mario Sunshine", platform: .gameCube, scheme: "sunpad",
      colors: ["#1E88E5", "#FFB300", "#00ACC1"], symbol: "sun.max.fill",
      embedded: Embedded(framework: "SunPadGame", module: "gGMSE01_recomp.dylib"), artID: "GMSE01"),
    Game(
      id: "meleepad", title: "Super Smash Bros. Melee", platform: .gameCube, scheme: "meleepad",
      colors: ["#C62828", "#37474F", "#FF7043"], symbol: "flame.fill",
      embedded: Embedded(framework: "MeleePadGame", module: "gGALE01r2_recomp.dylib"), artID: "GALE01"),
    Game(
      id: "windwaker", title: "The Legend of Zelda: The Wind Waker", platform: .gameCube,
      scheme: "bluewake", colors: ["#0277BD", "#26A69A", "#FFCA28"], symbol: "sailboat.fill",
      embedded: Embedded(framework: "BlueWakeGame", module: "gGZLE01_recomp.dylib"),
      artID: "GZLE01"),
    Game(
      id: "wonder", title: "Super Mario Bros. Wonder", platform: .nintendoSwitch,
      scheme: "nxnative-010015100b514000", colors: ["#7B1FA2", "#FDD835", "#43A047"],
      symbol: "sparkles", embedded: Embedded(framework: "Switch010015100B514000"), artID: "AQMXA"),
    Game(
      id: "acnh", title: "Animal Crossing: New Horizons", platform: .nintendoSwitch,
      scheme: "nxnative-01006f8002326000", colors: ["#2E7D32", "#FFEE58", "#4FC3F7"],
      symbol: "leaf.fill", embedded: Embedded(framework: "Switch01006F8002326000"), artID: "ACBAA"),
  ]

  static let customPalettes: [[String]] = [
    ["#3949AB", "#00BCD4", "#7E57C2"], ["#EF6C00", "#FDD835", "#D84315"],
    ["#00897B", "#C0CA33", "#26A69A"], ["#AD1457", "#7C4DFF", "#F06292"],
  ]
}

extension Color {
  init(hex: String) {
    var value: UInt64 = 0
    Scanner(string: hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))).scanHexInt64(&value)
    self.init(
      red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255)
  }
}
