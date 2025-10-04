import SwiftUI

enum SplashPhase: Equatable {
    case idle
    case looping
    case ready
    case unlocking
    case completed
}

struct SplashScreen: View {
    @Binding var phase: SplashPhase
    let onReadyToUnlock: () async -> Void

    @State private var ballOffset: CGFloat = -80
    @State private var chainProgress: CGFloat = 0
    @State private var isLooping = true
    @State private var loopTask: Task<Void, Never>? = nil
    @State private var gateOpenAmount: CGFloat = 0
    @State private var gateGlow: Double = 0
    @State private var pendingUnlock = false
    @State private var shouldSnapToFloor = false
    @State private var loopHeight: CGFloat = 0
    @State private var hasRunGateSequence = false

    var body: some View {
        ZStack {
            LinedPaperBackground(spacing: 52, marginX: 72)

            VStack(spacing: 28) {
                Spacer()

                Text("YOU AND GOALS")
                    .font(.handDrawn(size: 44, weight: .bold))
                    .foregroundStyle(Color.paperSpeck.opacity(0.92))
                    .shadow(color: Color.paperSpeck.opacity(0.3), radius: 5, x: 0, y: 2)
                Text("Loading your board…")
                    .font(.handDrawn(size: 22))
                    .foregroundStyle(Color.paperSpeck.opacity(0.75))

                ZStack {
                    HempTexture(density: 3600)
                        .frame(height: 160)
                        .opacity(0.44)

                    gateOverlay
                }
                .frame(height: 220)

                Spacer()

                Text(loopCaption)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color.paperLine.opacity(0.85))
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 40)
        }
        .task(id: phase) {
            await handlePhaseChange()
        }
    }

    private var loopCaption: String {
        switch phase {
        case .looping:
            return "Holding until setup completes…"
        case .ready:
            return "Wrapping up checks…"
        case .unlocking:
            return "Opening workspace…"
        case .completed:
            return "Welcome back!"
        default:
            return "Preparing"
        }
    }

    private var bouncingBall: some View {
        GeometryReader { proxy in
            let height = proxy.size.height

            ZStack {
                HempTexture()
                    .frame(width: 130, height: height)
                    .opacity(0.47)

                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.paperMargin.opacity(0.95), Color.paperMargin.opacity(0.55)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 30
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(
                        Circle()
                            .stroke(Color.paperSpeck.opacity(0.6), lineWidth: 1.6)
                    )
                    .shadow(color: Color.paperSpeck.opacity(0.45), radius: 12, x: 0, y: 4)
                    .overlay(
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 0.6, dash: [4, 4]))
                            .foregroundStyle(Color.white.opacity(0.35))
                            .blur(radius: 0.5)
                    )
                    .offset(y: ballOffset)
                    .rotationEffect(.degrees(shouldSnapToFloor ? 4 : -6), anchor: .center)
                    .animation(.easeOut(duration: 0.18), value: shouldSnapToFloor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: phase) {
                await updateLoop(for: height)
            }
        }
        .padding(.horizontal, 80)
    }

    private var gateOverlay: some View {
        GeometryReader { proxy in
            ZStack {
                CurtainsOverlay(openAmount: gateOpenAmount)
                    .frame(width: proxy.size.width * 1.2, height: proxy.size.height * 2)

                ChainsOverlay(chainProgress: chainProgress)
                    .frame(width: proxy.size.width, height: proxy.size.height)

                GateGlowOverlay(opacity: gateGlow)
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
    }

    private func loopMotion(height: CGFloat) async {
        guard !Task.isCancelled else { return }

        let bottom = height / 2 - 60
        let top = -height / 2 + 60

        await MainActor.run {
            ballOffset = top
        }

        while !Task.isCancelled && isLooping {
            await MainActor.run {
                withAnimation(.interpolatingSpring(stiffness: 130, damping: 11)) {
                    ballOffset = bottom
                }
                shouldSnapToFloor = true
            }

            try? await Task.sleep(nanoseconds: 780_000_000)
            guard !Task.isCancelled && isLooping else { break }

            await MainActor.run {
                withAnimation(.interpolatingSpring(stiffness: 130, damping: 11)) {
                    ballOffset = top
                }
                shouldSnapToFloor = false
            }

            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private func startLoop(height: CGFloat) {
        guard loopTask == nil else { return }
        isLooping = true
        loopTask = Task {
            await loopMotion(height: height)
        }
    }

    private func cancelLoop() {
        loopTask?.cancel()
        loopTask = nil
        isLooping = false
        shouldSnapToFloor = false
    }

    private func resetGate() {
        gateOpenAmount = 0
        chainProgress = 0
        gateGlow = 0
        hasRunGateSequence = false
    }

    private func triggerGateOpen(height: CGFloat) {
        let clampedHeight = max(height, 1)
        let targetOpen = min(1, clampedHeight / 120)

        withAnimation(.easeInOut(duration: 1.5)) {
            gateOpenAmount = targetOpen
            chainProgress = 1
            gateGlow = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.9)) {
                gateGlow = 0
            }
        }
    }

    private func startGateSequence() {
        guard !hasRunGateSequence else { return }
        hasRunGateSequence = true

        cancelLoop()

        Task {
            if shouldSnapToFloor {
                try? await Task.sleep(nanoseconds: 120_000_000)
                await MainActor.run {
                    shouldSnapToFloor = false
                }
            }

            await MainActor.run {
                triggerGateOpen(height: loopHeight)
            }

            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await onReadyToUnlock()
        }
    }
    
    private func handlePhaseChange() async {
        switch phase {
        case .idle:
            break
        case .looping:
            await MainActor.run {
                isLooping = true
                shouldSnapToFloor = false
                pendingUnlock = false
                hasRunGateSequence = false
                resetGate()
            }
        case .ready:
            await MainActor.run {
                pendingUnlock = true
            }
        case .unlocking:
            await MainActor.run {
                startGateSequence()
            }
        case .completed:
            await MainActor.run {
                cancelLoop()
            }
        }
    }
    
    private func updateLoop(for height: CGFloat) async {
        await MainActor.run {
            loopHeight = height
        }

        guard phase == .looping || phase == .ready else { return }

        await MainActor.run {
            startLoop(height: height)
        }
    }
}

private struct HempTexture: View {
    var density: Double = 5000

    var body: some View {
        Canvas { context, size in
            let grainDensity = Int(size.width * size.height / density)
            for _ in 0..<grainDensity {
                let x = Double.random(in: 0...size.width)
                let y = Double.random(in: 0...size.height)
                let w = Double.random(in: 5...16)
                let h = Double.random(in: 1...3.8)

                let path = Path(
                    roundedRect: CGRect(x: x, y: y, width: w, height: h),
                    cornerRadius: 1.4
                )

                context.fill(
                    path,
                    with: .color(Color.paperSpeck.opacity(Double.random(in: 0.1...0.26)))
                )
            }
        }
        .blendMode(.multiply)
    }
}

private struct CurtainsOverlay: View {
    var openAmount: CGFloat

    var body: some View {
        GeometryReader { proxy in
        let clamped = max(0, min(1, openAmount))
            let width = proxy.size.width
            let height = proxy.size.height
            let panelWidth = width / 2 + 180
            let panelHeight = height * 1.5
            let travel = width / 2 + panelWidth * 0.8
            let leftClosed = -width / 2 + panelWidth / 2
            let rightClosed = width / 2 - panelWidth / 2

            ZStack {
                curtainPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .offset(x: leftClosed - travel * clamped, y: -height * 0.25)

                curtainPanel
                    .frame(width: panelWidth, height: panelHeight)
                    .scaleEffect(x: -1, y: 1)
                    .offset(x: rightClosed + travel * clamped, y: -height * 0.25)
            }
            .frame(width: width, height: height)
        }
    }

    private var curtainPanel: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.paperDeep.opacity(0.95),
                            Color.paperSecondary.opacity(0.92),
                            Color.paperBase.opacity(0.9)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .stroke(Color.paperSpeck.opacity(0.55), lineWidth: 1.6)
                )
                .shadow(color: Color.paperSpeck.opacity(0.35), radius: 20, x: 0, y: 14)
                .overlay(
                    HempTexture(density: 4200)
                        .opacity(0.28)
                )

            RaggedEdge()
                .stroke(
                    Color.paperSpeck.opacity(0.6),
                    style: StrokeStyle(lineWidth: 1.3, dash: [5, 6], dashPhase: 2)
                )
                .padding(.horizontal, 24)
                .padding(.top, 26)
                .opacity(0.9)
        }
    }
}

private struct ChainsOverlay: View {
    var chainProgress: CGFloat

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let clamped = max(0, min(1, chainProgress))
                guard clamped > 0 else { return }

                let chainHeight = size.height * clamped
                let loopSpacing: Double = 18
                let loopRadius: Double = 3.5
                let columns: [Double] = [size.width * 0.18, size.width * 0.5, size.width * 0.82]

                for x in columns {
                    var y: Double = 0
                    while y <= chainHeight {
                        let rect = CGRect(x: x - loopRadius, y: y, width: loopRadius * 2, height: loopRadius * 2)
                        let circle = Path(ellipseIn: rect)
                        context.stroke(circle, with: .color(Color.paperSpeck.opacity(0.68)), lineWidth: 1.2)
                        y += loopSpacing
                    }

                    if clamped >= 1 {
                        let barRect = CGRect(x: x - 6, y: chainHeight, width: 12, height: 4)
                        context.fill(Path(roundedRect: barRect, cornerRadius: 1.2), with: .color(Color.paperSpeck.opacity(0.75)))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

private struct GateGlowOverlay: View {
    var opacity: Double

    var body: some View {
        RadialGradient(
            colors: [
                Color.paperMargin.opacity(0.45),
                Color.paperMargin.opacity(0.1),
                Color.paperMargin.opacity(0)
            ],
            center: .center,
            startRadius: 24,
            endRadius: 320
        )
        .opacity(opacity)
        .blendMode(.screen)
    }
}

private struct RaggedEdge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step = rect.width / 22
        let baseline = rect.midY

        path.move(to: CGPoint(x: rect.minX, y: baseline))

        for index in 0...22 {
            let x = rect.minX + CGFloat(index) * step
            let offset = Double.random(in: -5.5...5.5)
            path.addLine(to: CGPoint(x: x, y: baseline + offset))
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: baseline - 2))

        return path
    }
}


