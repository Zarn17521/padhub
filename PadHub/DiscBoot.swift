import SwiftUI

/// The launch screen over a GameCube game while it starts: its disc spinning
/// up in the drive, the game's box art printed as the label, until the game
/// shows its first frame (GameHost takes it down).
struct DiscBootView: View {
  let game: Game
  /// The disc's own scan (GameTDB), else the box art as its label.
  let disc: UIImage?
  let cover: UIImage?
  @State private var start = Date()
  @State private var shown = false

  var body: some View {
    GeometryReader { proxy in
      let size = min(proxy.size.width, proxy.size.height) * 0.52
      ZStack {
        Color.black.ignoresSafeArea()
        RadialGradient(
          colors: [(game.palette.first ?? .indigo).opacity(0.5), .clear], center: .center,
          startRadius: 0, endRadius: size * 1.5
        )
        .ignoresSafeArea()
        .opacity(shown ? 1 : 0)

        VStack(spacing: size * 0.16) {
          TimelineView(.animation) { timeline in
            GameCubeDisc(disc: disc, cover: cover)
              .frame(width: size, height: size)
              .rotationEffect(.degrees(Self.spin(after: timeline.date.timeIntervalSince(start))))
              // The light stays where it is while the disc turns under it.
              .overlay(DiscSheen().frame(width: size, height: size))
              .rotation3DEffect(.degrees(16), axis: (x: 1, y: 0, z: 0), perspective: 0.45)
              .shadow(color: (game.palette.first ?? .white).opacity(0.45), radius: size * 0.12)
          }
          VStack(spacing: 6) {
            Text(game.title)
              .font(.title3.weight(.bold))
              .foregroundStyle(.white)
              .multilineTextAlignment(.center)
            Text("Starting")
              .font(.footnote.weight(.semibold))
              .foregroundStyle(.white.opacity(0.55))
              .phaseAnimator([0.35, 1]) { content, opacity in
                content.opacity(opacity)
              } animation: { _ in .easeInOut(duration: 0.9) }
          }
          .padding(.horizontal, 24)
        }
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
      }
      .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .onAppear {
      start = Date()
      withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) { shown = true }
    }
  }

  /// The disc's angle in degrees after `t` seconds: it spins up over a second
  /// and a half, to two and a half turns a second, as a drive does.
  static func spin(after t: TimeInterval) -> Double {
    let top = 900.0
    let rampUp = 1.5
    return t < rampUp ? top * t * t / (2 * rampUp) : top * (t - rampUp / 2)
  }
}

/// A GameCube mini-disc seen from its label side: the game's own disc when
/// its scan is there; otherwise one drawn with the box art as its label, the
/// iridescent data side at the rim, the clear hub and its hole.
struct GameCubeDisc: View {
  let disc: UIImage?
  let cover: UIImage?

  var body: some View {
    if let disc {
      scanned(disc)
    } else {
      drawn
    }
  }

  private func scanned(_ disc: UIImage) -> some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Image(uiImage: disc)
          .resizable()
          .interpolation(.high)
          .antialiased(true)
          .scaledToFit()
        Circle().stroke(Color.white.opacity(0.35), lineWidth: 1.5)
      }
      .mask(Ring(inner: 0.15, outer: 1).fill(style: FillStyle(eoFill: true)))
      .frame(width: side, height: side)
    }
  }

  private var drawn: some View {
    GeometryReader { proxy in
      let side = min(proxy.size.width, proxy.size.height)
      ZStack {
        Circle()
          .fill(
            AngularGradient(
              colors: [
                Color(white: 0.85), Color(red: 0.70, green: 0.85, blue: 1.0),
                Color(red: 0.85, green: 0.76, blue: 1.0), Color(red: 1.0, green: 0.78, blue: 0.86),
                Color(red: 1.0, green: 0.92, blue: 0.70), Color(red: 0.74, green: 1.0, blue: 0.88),
                Color(white: 0.85),
              ], center: .center))
        label
          .frame(width: side, height: side)
          .mask(Ring(inner: 0.34, outer: 0.93).fill(style: FillStyle(eoFill: true)))
        // The clear plastic hub, with its moulded rings.
        Ring(inner: 0.15, outer: 0.34)
          .fill(Color.white.opacity(0.16), style: FillStyle(eoFill: true))
        Circle().stroke(Color.white.opacity(0.35), lineWidth: 1).frame(width: side * 0.34, height: side * 0.34)
        Circle().stroke(Color.white.opacity(0.22), lineWidth: 1).frame(width: side * 0.26, height: side * 0.26)
        Circle().stroke(Color.white.opacity(0.45), lineWidth: 1.5)
      }
      // The hole goes through.
      .mask(Ring(inner: 0.15, outer: 1).fill(style: FillStyle(eoFill: true)))
      .frame(width: side, height: side)
    }
  }

  @ViewBuilder private var label: some View {
    if let cover {
      Image(uiImage: cover)
        .resizable()
        .scaledToFill()
    } else {
      LinearGradient(colors: [.indigo, .purple], startPoint: .top, endPoint: .bottom)
    }
  }
}

/// A light falling across the spinning disc.
private struct DiscSheen: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0.2), .init(color: .white.opacity(0.32), location: 0.42),
        .init(color: .clear, location: 0.58), .init(color: .white.opacity(0.12), location: 0.78),
        .init(color: .clear, location: 0.9),
      ], startPoint: .topLeading, endPoint: .bottomTrailing
    )
    .blendMode(.screen)
    .mask(Ring(inner: 0.15, outer: 1).fill(style: FillStyle(eoFill: true)))
    .allowsHitTesting(false)
  }
}

/// The ring between two radii, as fractions of the shape's radius (drawn with
/// the even-odd rule).
struct Ring: Shape {
  var inner: CGFloat
  var outer: CGFloat

  func path(in rect: CGRect) -> Path {
    let radius = min(rect.width, rect.height) / 2
    let center = CGPoint(x: rect.midX, y: rect.midY)
    var path = Path()
    for fraction in [outer, inner] where fraction > 0 {
      let r = radius * fraction
      path.addEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }
    return path
  }
}
