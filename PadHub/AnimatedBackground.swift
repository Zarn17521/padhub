import SwiftUI

/// A slowly drifting mesh of the selected game's colors.
struct AnimatedBackground: View {
  let palette: [Color]
  /// Still while a game is in front, so the menu takes no GPU time from it.
  var paused = false

  var body: some View {
    TimelineView(.animation(minimumInterval: nil, paused: paused)) { timeline in
      let t = timeline.date.timeIntervalSinceReferenceDate
      MeshGradient(
        width: 3, height: 3,
        points: points(at: t),
        colors: colors)
    }
    .overlay(
      LinearGradient(
        colors: [.black.opacity(0.15), .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
    )
    .ignoresSafeArea()
  }

  private var colors: [Color] {
    let a = palette.first ?? .blue
    let b = palette.count > 1 ? palette[1] : a
    let c = palette.count > 2 ? palette[2] : b
    return [
      a, a.mix(with: .black, by: 0.35), b.mix(with: .black, by: 0.55),
      c.mix(with: .black, by: 0.45), a.mix(with: b, by: 0.5), b,
      .black, c.mix(with: .black, by: 0.6), a.mix(with: .black, by: 0.7),
    ]
  }

  private func points(at t: Double) -> [SIMD2<Float>] {
    func drift(_ base: Float, _ speed: Double, _ phase: Double, _ amount: Float = 0.12) -> Float {
      base + Float(sin(t * speed + phase)) * amount
    }
    return [
      [0, 0], [0.5, 0], [1, 0],
      [0, drift(0.5, 0.31, 0)], [drift(0.5, 0.23, 1.3), drift(0.5, 0.29, 2.1)], [1, drift(0.5, 0.27, 3.4)],
      [0, 1], [drift(0.5, 0.19, 4.2), 1], [1, 1],
    ]
  }
}
