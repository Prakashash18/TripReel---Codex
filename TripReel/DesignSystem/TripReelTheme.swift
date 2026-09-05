import SwiftUI

enum TR {
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

enum WarmBackgroundVariant {
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
                if usesSecondGlow {
                    RadialGradient(
                        colors: [second.opacity(0.85), second.opacity(0)],
                        center: .init(x: 0.91, y: variant == .pace ? 0.95 : 0.18),
                        startRadius: 0,
                        endRadius: proxy.size.width * 1.15
                    )
                }
            }
        }
        .ignoresSafeArea()
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TR.ui(17, weight: .semibold))
            .foregroundStyle(TR.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(TR.cream.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct GlassButtonStyle: ButtonStyle {
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
}
