import SwiftUI

enum SplashPhase: Equatable {
    case idle
    case loading        // Ball bouncing while preloading
    case readyToStart   // Ball at rest, START button visible
    case unlocking      // Gate opening animation
    case completed
}

struct SplashScreen: View {
    @Binding var phase: SplashPhase
    let onReadyToUnlock: () async -> Void

    @State private var ballY: CGFloat = 0
    @State private var ballRotation: Double = 0
    @State private var ballScale: CGFloat = 1.0
    @State private var ballGlow: Double = 0.3
    
    @State private var chainProgress: CGFloat = 0
    @State private var loopTask: Task<Void, Never>? = nil
    @State private var gateOpenAmount: CGFloat = 0
    @State private var gateGlow: Double = 0
    @State private var loopHeight: CGFloat = 0
    @State private var hasRunGateSequence = false
    
    @State private var buttonOpacity: Double = 0
    @State private var buttonScale: CGFloat = 0.6
    @State private var buttonY: CGFloat = 30
    @State private var didSettleForReady = false
    @State private var pendingReadySettle = false

    var body: some View {
        ZStack {
            LinedPaperBackground(spacing: 52, marginX: 72)

            VStack(spacing: 32) {
                Spacer()

                Text("YOU AND GOALS")
                    .font(.handDrawn(size: 48, weight: .bold))
                    .foregroundStyle(Color.paperSpeck.opacity(0.95))
                    .shadow(color: Color.paperSpeck.opacity(0.25), radius: 8, x: 0, y: 3)
                
                Text(statusText)
                    .font(.handDrawn(size: 20))
                    .foregroundStyle(Color.paperSpeck.opacity(0.7))
                    .animation(.easeInOut(duration: 0.4), value: statusText)

                ZStack {
                    gateOverlay
                        .frame(height: 260)
                    
                    bouncingBall
                        .frame(height: 200)
                    
                    // START button appears when ready
                    if phase == .readyToStart {
                        startButton
                            .opacity(buttonOpacity)
                            .scaleEffect(buttonScale)
                            .offset(y: buttonY)
                            .zIndex(10)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 260)

                Spacer()

                Text(captionText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.paperLine.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut(duration: 0.4), value: captionText)
                    .padding(.bottom, 50)
            }
            .padding(.horizontal, 40)
        }
        .task(id: phase) {
            await handlePhaseChange()
        }
    }

    private var statusText: String {
        switch phase {
        case .idle: return ""
        case .loading: return "Loading your board…"
        case .readyToStart: return "Ready when you are"
        case .unlocking: return "Opening workspace…"
        case .completed: return "Welcome!"
        }
    }

    private var captionText: String {
        switch phase {
        case .loading: return "Preparing goals & insights"
        case .readyToStart: return "Tap START to begin"
        case .unlocking: return "Entering your workspace"
        default: return ""
        }
    }

    private var bouncingBall: some View {
        GeometryReader { geo in
            let height = geo.size.height
            
            ZStack {
                // Shadow
                Ellipse()
                    .fill(Color.paperSpeck.opacity(0.15))
                    .frame(width: 70 * (1.15 - ballScale * 0.15), height: 10)
                    .blur(radius: 6)
                    .offset(y: height / 2 - 5)
                
                // Ball with glow
                ZStack {
                    // Glow
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.paperMargin.opacity(ballGlow * 0.5),
                                    Color.paperMargin.opacity(0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: 35
                            )
                        )
                        .frame(width: 70, height: 70)
                        .blur(radius: 8)
                    
                    // Main ball
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.paperMargin.opacity(0.95),
                                    Color.paperMargin.opacity(0.7)
                                ],
                                center: UnitPoint(x: 0.35, y: 0.35),
                                startRadius: 0,
                                endRadius: 26
                            )
                        )
                        .frame(width: 52, height: 52)
                        .overlay(
                            Circle()
                                .stroke(Color.paperSpeck.opacity(0.5), lineWidth: 1.5)
                        )
                        .overlay(
                            Circle()
                                .fill(Color.white.opacity(0.3))
                                .frame(width: 16, height: 16)
                                .offset(x: -9, y: -9)
                                .blur(radius: 2)
                        )
                        .shadow(color: Color.paperSpeck.opacity(0.3), radius: 10, x: 0, y: 5)
                }
                .scaleEffect(ballScale)
                .rotationEffect(.degrees(ballRotation))
                .offset(y: ballY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                await MainActor.run {
                    loopHeight = height
                }
                if phase == .readyToStart && pendingReadySettle {
                    pendingReadySettle = false
                    await settleToFloor(floorY: height / 2 - 26)
                }
                await startBounceLoopIfNeeded(using: height)
            }
        }
    }
    
    private var startButton: some View {
        Button {
            triggerUnlock()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24, weight: .semibold))
                
                Text("START")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 38)
            .padding(.vertical, 18)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.paperMargin)
                        .blur(radius: 16)
                        .opacity(0.5)
                    
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.paperMargin.opacity(0.95),
                                    Color.paperMargin.opacity(0.8)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.white.opacity(0.4), Color.white.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1.5
                                )
                        )
                        .shadow(color: Color.paperSpeck.opacity(0.35), radius: 12, x: 0, y: 6)
                }
            )
        }
        .buttonStyle(PressButtonStyle())
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

    // MARK: - Ball Animation
    
    private func startBounceLoopIfNeeded(using measuredHeight: CGFloat? = nil) async {
        await MainActor.run {
            if let measuredHeight {
                loopHeight = measuredHeight
            }

            guard loopTask == nil, phase == .loading else { return }
            let effectiveHeight = max(loopHeight, 60)

            loopTask = Task {
                await bounceLoop(height: effectiveHeight)
            }
        }
    }

    private func resetForLoading() {
        loopTask?.cancel()
        loopTask = nil
        buttonOpacity = 0
        buttonScale = 0.6
        buttonY = 30
        gateOpenAmount = 0
        chainProgress = 0
        gateGlow = 0
        ballY = 0
        ballScale = 1
        ballGlow = 0.3
        ballRotation = 0
        didSettleForReady = false
        pendingReadySettle = false
        hasRunGateSequence = false
    }

    private func bounceLoop(height: CGFloat) async {
        let floorY = height / 2 - 26
        let ceilingY = -height / 2 + 26

        await MainActor.run {
            ballY = ceilingY
            ballRotation = 0
        }

        while !Task.isCancelled && phase == .loading {
            await MainActor.run {
                withAnimation(.timingCurve(0.35, 0, 0.65, 1, duration: 0.65)) {
                    ballY = floorY
                    ballRotation += 180
                    ballScale = 0.92
                    ballGlow = 0.7
                }
            }

            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled && phase == .loading else { break }

            await MainActor.run {
                withAnimation(.timingCurve(0.35, 0, 0.3, 1, duration: 0.55)) {
                    ballY = ceilingY
                    ballRotation += 180
                    ballScale = 1.0
                    ballGlow = 0.3
                }
            }

            try? await Task.sleep(nanoseconds: 550_000_000)
        }

        await MainActor.run {
            loopTask = nil
        }

        if phase == .readyToStart {
            await settleToFloor(floorY: floorY)
        }
    }
    
    private func settleToFloor(floorY: CGFloat) async {
        guard !didSettleForReady else { return }

        await MainActor.run {
            withAnimation(.timingCurve(0.4, 0, 0.7, 1, duration: 0.5)) {
                ballY = floorY
                ballScale = 0.95
                ballGlow = 0
            }
        }

        try? await Task.sleep(nanoseconds: 500_000_000)

        await MainActor.run {
            withAnimation(.interpolatingSpring(stiffness: 180, damping: 14)) {
                ballY = floorY - 10
                ballScale = 0.97
            }
        }

        try? await Task.sleep(nanoseconds: 250_000_000)

        await MainActor.run {
            withAnimation(.interpolatingSpring(stiffness: 160, damping: 12)) {
                ballY = floorY
                ballScale = 1.0
            }
        }

        try? await Task.sleep(nanoseconds: 150_000_000)
        await showStartButton()
    }
    
    private func showStartButton() async {
        await MainActor.run {
            guard !didSettleForReady else { return }
            didSettleForReady = true
            withAnimation(.interpolatingSpring(stiffness: 140, damping: 14).delay(0.1)) {
                buttonOpacity = 1.0
                buttonScale = 1.0
                buttonY = 0
            }
        }
    }
    
    private func triggerUnlock() {
        // Haptic
        let impact = UIImpactFeedbackGenerator(style: .medium)
        impact.impactOccurred()
        
        // Hide button
        withAnimation(.easeOut(duration: 0.2)) {
            buttonOpacity = 0
            buttonScale = 0.8
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            
            await MainActor.run {
                phase = .unlocking
            }
        }
    }

    // MARK: - Gate Animation
    
    private func triggerGateOpen() {
        guard !hasRunGateSequence else { return }
        hasRunGateSequence = true
        withAnimation(.easeInOut(duration: 1.3)) {
            gateOpenAmount = 1.0
            chainProgress = 1.0
            gateGlow = 1.0
        }
        
        // Ball rises and fades
        withAnimation(.easeOut(duration: 1.0)) {
            ballY = -180
            ballScale = 0.6
            ballGlow = 0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            withAnimation(.easeOut(duration: 0.6)) {
                gateGlow = 0
            }
        }
        
        Task {
            try? await Task.sleep(nanoseconds: 1_100_000_000)
            await onReadyToUnlock()
        }
    }
    
    // MARK: - Phase Handling
    
    private func handlePhaseChange() async {
        switch phase {
        case .idle:
            break
            
        case .loading:
            await MainActor.run {
                resetForLoading()
            }
            await startBounceLoopIfNeeded(using: loopHeight)
            
        case .readyToStart:
            if loopHeight == 0 {
                pendingReadySettle = true
            } else {
                await settleToFloor(floorY: loopHeight / 2 - 26)
            }
            
        case .unlocking:
            await MainActor.run {
                triggerGateOpen()
            }
            
        case .completed:
            await MainActor.run {
                loopTask?.cancel()
                loopTask = nil
            }
        }
    }
}

// MARK: - Button Style

struct PressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Supporting Views

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


