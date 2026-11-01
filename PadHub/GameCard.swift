import SwiftUI

/// A game's cover: the player's picture when they chose one, else a card
/// drawn from the game's colors and symbol.
struct GameCard: View {
  let game: Game
  let cover: UIImage?
  let installed: Bool
  let selected: Bool

  @State private var shine = false

  var body: some View {
    let palette = game.palette
    ZStack {
      if let cover {
        Image(uiImage: cover).resizable().scaledToFill()
      } else {
        LinearGradient(
          colors: [palette[0], palette.count > 1 ? palette[1] : palette[0]],
          startPoint: .topLeading, endPoint: .bottomTrailing)
        Image(systemName: game.symbol)
          .font(.system(size: 92, weight: .bold))
          .foregroundStyle(.white.opacity(0.9))
          .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
          .offset(y: -30)
          .symbolEffect(.bounce, value: selected)
      }
      VStack(alignment: .leading, spacing: 6) {
        Spacer()
        Label(game.platform.label, systemImage: game.platform.symbol)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(.ultraThinMaterial, in: Capsule())
        Text(game.title)
          .font(.title3.weight(.heavy))
          .foregroundStyle(.white)
          .lineLimit(2)
          .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
      .background(
        LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
      // A sweep of light across the selected card.
      LinearGradient(
        colors: [.clear, .white.opacity(selected ? 0.35 : 0), .clear], startPoint: .leading,
        endPoint: .trailing
      )
      .rotationEffect(.degrees(20))
      .offset(x: shine ? 320 : -320)
      .blendMode(.plusLighter)
    }
    .frame(width: 240, height: 340)
    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 28, style: .continuous)
        .strokeBorder(.white.opacity(selected ? 0.9 : 0.15), lineWidth: selected ? 3 : 1)
    )
    .saturation(installed ? 1 : 0.15)
    .overlay(alignment: .topTrailing) {
      if !installed {
        Text("Not installed")
          .font(.caption2.weight(.bold))
          .padding(.horizontal, 8).padding(.vertical, 4)
          .background(.black.opacity(0.6), in: Capsule())
          .padding(12)
      }
    }
    .shadow(color: (palette.first ?? .black).opacity(selected ? 0.75 : 0.25), radius: selected ? 30 : 12, y: 12)
    .onChange(of: selected) { _, isSelected in
      guard isSelected else { return }
      shine = false
      withAnimation(.easeInOut(duration: 0.9)) { shine = true }
    }
  }
}
