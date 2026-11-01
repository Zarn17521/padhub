import SwiftUI

/// A game's cover: the player's picture or the game's box art, else a card
/// drawn from the game's colors and symbol.
struct GameCard: View {
  let game: Game
  let cover: UIImage?
  let installed: Bool
  let selected: Bool
  /// The game waits behind the menu, where the player left it.
  var paused = false

  /// Its full size, the shape of a GameCube case.
  static let size = CGSize(width: 240, height: 340)

  @State private var shine = false

  var body: some View {
    let palette = game.palette
    ZStack {
      if let cover {
        CoverImage(image: cover)
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
        HStack(spacing: 6) {
          Label(game.platform.label, systemImage: game.platform.symbol)
          if paused {
            Label("Paused", systemImage: "pause.fill")
              .transition(.scale.combined(with: .opacity))
          }
        }
        .font(.caption.weight(.semibold))
        .labelStyle(PillLabelStyle())
        // The box art carries the title already.
        if cover == nil {
          Text(game.title)
            .font(.title3.weight(.heavy))
            .foregroundStyle(.white)
            .lineLimit(2)
            .shadow(color: .black.opacity(0.5), radius: 6, y: 2)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(18)
      .background(
        LinearGradient(
          colors: [.clear, .black.opacity(cover == nil ? 0.55 : 0.35)], startPoint: .center,
          endPoint: .bottom))
      .animation(.spring(response: 0.4, dampingFraction: 0.7), value: paused)
      // A sweep of light across the selected card.
      LinearGradient(
        colors: [.clear, .white.opacity(selected ? 0.35 : 0), .clear], startPoint: .leading,
        endPoint: .trailing
      )
      .rotationEffect(.degrees(20))
      .offset(x: shine ? 320 : -320)
      .blendMode(.plusLighter)
    }
    .frame(width: Self.size.width, height: Self.size.height)
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

private struct PillLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    Label(configuration)
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(.ultraThinMaterial, in: Capsule())
  }
}

/// Box art fills the card when it has the card's shape (a GameCube case);
/// taller art (a Switch case) shows whole, over a blurred copy of itself.
private struct CoverImage: View {
  let image: UIImage

  var body: some View {
    let ratio = image.size.width / max(image.size.height, 1)
    if abs(ratio - GameCard.size.width / GameCard.size.height) < 0.04 {
      Image(uiImage: image).resizable().scaledToFill()
    } else {
      ZStack {
        Image(uiImage: image).resizable().scaledToFill()
          .blur(radius: 18)
          .overlay(Color.black.opacity(0.25))
        Image(uiImage: image).resizable().scaledToFit()
          .shadow(color: .black.opacity(0.4), radius: 10)
      }
    }
  }
}
