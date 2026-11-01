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

/// A game app on this phone, opened through its URL scheme.
struct Game: Identifiable, Codable, Hashable {
  var id: String
  var title: String
  var platform: Platform
  /// Without "://": SunPad registers "sunpad", nxnative "nxnative-<title ID>".
  var scheme: String
  /// Hex colors for the card and the background, first one dominant.
  var colors: [String]
  var symbol: String
  var isCustom = false

  var url: URL? { URL(string: "\(scheme)://") }
  var palette: [Color] { colors.map(Color.init(hex:)) }
}

extension Game {
  /// Games built in this repository's sibling projects.
  static let catalog: [Game] = [
    Game(
      id: "sunpad", title: "Super Mario Sunshine", platform: .gameCube, scheme: "sunpad",
      colors: ["#1E88E5", "#FFB300", "#00ACC1"], symbol: "sun.max.fill"),
    Game(
      id: "meleepad", title: "Super Smash Bros. Melee", platform: .gameCube, scheme: "meleepad",
      colors: ["#C62828", "#37474F", "#FF7043"], symbol: "flame.fill"),
    Game(
      id: "wonder", title: "Super Mario Bros. Wonder", platform: .nintendoSwitch,
      scheme: "nxnative-010015100b514000", colors: ["#7B1FA2", "#FDD835", "#43A047"],
      symbol: "sparkles"),
    Game(
      id: "acnh", title: "Animal Crossing: New Horizons", platform: .nintendoSwitch,
      scheme: "nxnative-01006f8002326000", colors: ["#2E7D32", "#FFEE58", "#4FC3F7"],
      symbol: "leaf.fill"),
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
