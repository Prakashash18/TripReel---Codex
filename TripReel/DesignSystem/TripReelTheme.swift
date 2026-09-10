import SwiftUI

enum TR {
    static let appName = "Memories"
    static let tagline = "Turn the photos that matter into a story."
    static let cream = Color(red: 0.992, green: 0.980, blue: 0.961)
    static let ink = Color(red: 0.090, green: 0.067, blue: 0.047)
    static let accent = Color(red: 0.941, green: 0.706, blue: 0.369)
    static let keep = Color(red: 0.561, green: 0.863, blue: 0.608)
    static let cut = Color(red: 1.000, green: 0.420, blue: 0.341)
    static let sheet = Color(red: 0.090, green: 0.059, blue: 0.035)

    static func display(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Regular", size: size, relativeTo: .largeTitle)
    }

    static func displayItalic(_ size: CGFloat) -> Font {
        .custom("InstrumentSerif-Italic", size: size, relativeTo: .largeTitle)
    }

    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

enum TRNavigationDirection: Equatable, Sendable {
    case forward
    case backward
    case replace
}

/// One motion language for the whole app. Short springs provide tactile UI
/// feedback, while the longer timing curve is reserved for film playback.
/// Keeping these values centralized prevents screens from accumulating subtly
/// different animation personalities.
enum TRMotion {
    static let navigation = Animation.spring(duration: 0.46, bounce: 0.04)
    static let reveal = Animation.spring(duration: 0.52, bounce: 0.08)
    static let press = Animation.spring(duration: 0.18, bounce: 0.08)
    static let selection = Animation.spring(duration: 0.30, bounce: 0.10)
    static let gestureReturn = Animation.spring(duration: 0.34, bounce: 0.12)
    static let cardArrival = Animation.spring(duration: 0.38, bounce: 0.05)
    static let cardDismiss = Animation.timingCurve(0.18, 0.78, 0.24, 1, duration: 0.24)
    static let scrub = Animation.easeOut(duration: 0.12)
    static let progress = Animation.easeOut(duration: 0.28)
    static let overlay = Animation.easeInOut(duration: 0.24)
    static let imageLoad = Animation.easeInOut(duration: 0.22)
    static let ambient = Animation.easeInOut(duration: 11).repeatForever(autoreverses: true)

    static func montageDrift(duration: TimeInterval) -> Animation {
        .timingCurve(0.37, 0, 0.63, 1, duration: max(0.7, duration * 0.92))
    }

    static func screenTransition(
        direction: TRNavigationDirection,
        prefersCrossFade: Bool
    ) -> AnyTransition {
        guard !prefersCrossFade else { return .opacity }
        switch direction {
        case .forward:
            return .asymmetric(
                insertion: .opacity
                    .combined(with: .offset(x: 24, y: 0))
                    .combined(with: .scale(scale: 0.994)),
                removal: .opacity.combined(with: .offset(x: -11, y: 0))
            )
        case .backward:
            return .asymmetric(
                insertion: .opacity.combined(with: .offset(x: -18, y: 0)),
                removal: .opacity.combined(with: .offset(x: 24, y: 0))
            )
        case .replace:
            return .opacity.combined(with: .scale(scale: 0.994))
        }
    }
}

enum WarmBackgroundVariant: Hashable {
    case access
    case trips
    case building
    case cutting
    case pace
    case export
    case rendering
    case cleanup
}

struct WarmBackground: View {
    let variant: WarmBackgroundVariant
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    private var base: Color {
        switch variant {
        case .access: Color(red: 0.082, green: 0.043, blue: 0.024)
        case .trips: Color(red: 0.071, green: 0.039, blue: 0.024)
        case .building, .pace: Color(red: 0.063, green: 0.031, blue: 0.012)
        case .cutting: Color(red: 0.039, green: 0.027, blue: 0.020)
        case .export: Color(red: 0.059, green: 0.031, blue: 0.012)
        case .rendering: Color(red: 0.051, green: 0.027, blue: 0.012)
        case .cleanup: Color(red: 0.051, green: 0.031, blue: 0.020)
        }
    }

    private var first: Color {
        switch variant {
        case .access: Color(red: 0.788, green: 0.573, blue: 0.184)
        case .trips, .pace, .export: Color(red: 0.659, green: 0.443, blue: 0.165)
        case .building: Color(red: 0.690, green: 0.416, blue: 0.122)
        case .cutting: Color(red: 0.227, green: 0.110, blue: 0.031)
        case .rendering: Color(red: 0.541, green: 0.333, blue: 0.094)
        case .cleanup: Color(red: 0.490, green: 0.353, blue: 0.165)
        }
    }

    private var second: Color {
        switch variant {
        case .access: Color(red: 0.722, green: 0.329, blue: 0.122)
        case .trips: Color(red: 0.561, green: 0.239, blue: 0.090)
        case .pace: Color(red: 0.490, green: 0.184, blue: 0.071)
        default: Color.clear
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                base
                RadialGradient(
                    colors: [first.opacity(0.95), first.opacity(0)],
                    center: firstCenter,
                    startRadius: 0,
                    endRadius: proxy.size.width * firstRadius
                )
                .scaleEffect(drifting ? 1.045 : 0.985, anchor: firstCenter)
                .offset(
                    x: motionAllowed ? (drifting ? 9 : -7) : 0,
                    y: motionAllowed ? (drifting ? 5 : -4) : 0
                )
                if usesSecondGlow {
                    RadialGradient(
                        colors: [second.opacity(0.85), second.opacity(0)],
                        center: .init(x: 0.91, y: variant == .pace ? 0.95 : 0.18),
                        startRadius: 0,
                        endRadius: proxy.size.width * 1.15
                    )
                    .scaleEffect(drifting ? 0.97 : 1.035, anchor: .bottomTrailing)
                    .offset(
                        x: motionAllowed ? (drifting ? -8 : 6) : 0,
                        y: motionAllowed ? (drifting ? -4 : 5) : 0
                    )
                }
            }
        }
        .ignoresSafeArea()
        .task(id: reduceMotion) {
            drifting = false
            guard motionAllowed else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(TRMotion.ambient) {
                drifting = true
            }
        }
    }

    private var motionAllowed: Bool {
        !reduceMotion
    }

    private var usesSecondGlow: Bool {
        switch variant {
        case .access, .trips, .pace: true
        default: false
        }
    }

    private var firstCenter: UnitPoint {
        switch variant {
        case .building, .cutting, .rendering, .cleanup:
            .init(x: 0.5, y: 0.0)
        default:
            .init(x: 0.14, y: 0.02)
        }
    }

    private var firstRadius: CGFloat {
        switch variant {
        case .cleanup: 0.9
        case .cutting, .rendering: 1.0
        default: 1.15
        }
    }
}

struct CreamButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TR.ui(17, weight: .semibold))
            .foregroundStyle(TR.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(TR.cream.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.976 : 1)
            .shadow(
                color: .black.opacity(configuration.isPressed ? 0.18 : 0.28),
                radius: configuration.isPressed ? 14 : 24,
                y: configuration.isPressed ? 6 : 10
            )
            .animation(reduceMotion ? nil : TRMotion.press, value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TR.ui(16, weight: .semibold))
            .foregroundStyle(TR.cream)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.white.opacity(configuration.isPressed ? 0.13 : 0.055)
                }
            }
            .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.976 : 1)
            .brightness(configuration.isPressed ? 0.035 : 0)
            .animation(reduceMotion ? nil : TRMotion.press, value: configuration.isPressed)
    }
}

struct TactileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var pressedScale: CGFloat = 0.975

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .brightness(configuration.isPressed ? 0.045 : 0)
            .animation(reduceMotion ? nil : TRMotion.press, value: configuration.isPressed)
    }
}

private struct TRMotionEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false

    let delay: TimeInterval
    let distance: CGFloat

    private var motionReduced: Bool { reduceMotion }

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: motionReduced || visible ? 0 : distance)
            .scaleEffect(motionReduced || visible ? 1 : 0.992, anchor: .bottom)
            .task {
                if motionReduced {
                    visible = false
                    await Task.yield()
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.16)) {
                        visible = true
                    }
                    return
                }
                visible = false
                await Task.yield()
                guard !Task.isCancelled else { return }
                withAnimation(TRMotion.reveal.delay(delay)) {
                    visible = true
                }
            }
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 18, highlighted: Bool = false) -> some View {
        background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Color.white.opacity(highlighted ? 0.075 : 0.025)
            }
        }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(highlighted ? TR.accent.opacity(0.46) : .white.opacity(0.11), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// A brief, one-shot entrance for major screen regions. This never carries
    /// meaning by itself and becomes an opacity-only reveal with Reduce Motion.
    func trEntrance(_ order: Int = 0, distance: CGFloat = 12) -> some View {
        modifier(
            TRMotionEntranceModifier(
                delay: min(0.18, Double(max(0, order)) * 0.045),
                distance: distance
            )
        )
    }
}
