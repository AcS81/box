import SwiftUI

struct LinedPaperBackground: View {
    var spacing: CGFloat = 40
    var marginX: CGFloat = 68
    var seed: Double = 0

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lineCount = max(0, Int((size.height / spacing).rounded(.up)))

            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color.paperBase,
                        Color.paperSecondary,
                        Color.paperDeep.opacity(0.9)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                ForEach(0...lineCount, id: \.self) { index in
                    let y = CGFloat(index) * spacing
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    .stroke(Color.paperLine.opacity(0.75), lineWidth: 1.1)
                }

                Path { path in
                    path.move(to: CGPoint(x: marginX, y: 0))
                    path.addLine(to: CGPoint(x: marginX, y: size.height))
                }
                .stroke(Color.paperMargin.opacity(0.9), lineWidth: 2.4)

                SpeckleOverlay()
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
    }
}

private struct SpeckleOverlay: View {
    var density: Int = 160

    var body: some View {
        GeometryReader { proxy in
            let rect = proxy.frame(in: .local)
            Canvas { context, canvasSize in
                let seed = UInt64(rect.minX.rounded()) ^ UInt64(rect.minY.rounded()) ^ 0x9E3779B97F4A7C15
                var generator = SeededGenerator(seed: seed)

                for _ in 0..<density {
                    let x = Double.random(in: 0...canvasSize.width, using: &generator)
                    let y = Double.random(in: 0...canvasSize.height, using: &generator)
                    let radius = Double.random(in: 0.4...1.6, using: &generator)

                    var circle = Path()
                    circle.addEllipse(in: CGRect(x: x, y: y, width: radius, height: radius))

                    let opacity = Double.random(in: 0.22...0.45, using: &generator)
                    context.fill(circle, with: .color(Color.paperSpeck.opacity(opacity)))
                }
            }
            .blendMode(.multiply)
            .opacity(0.62)
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0xdeadbeef : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

extension View {
    func linedPaperBackground(spacing: CGFloat = 40, marginX: CGFloat = 68) -> some View {
        background(
            LinedPaperBackground(spacing: spacing, marginX: marginX)
        )
    }
}


