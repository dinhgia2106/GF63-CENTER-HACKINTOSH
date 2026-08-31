import SwiftUI

enum R3Theme {
    static let accent = Color(red: 1.00, green: 0.20, blue: 0.34)
    static let cyan = Color(red: 0.20, green: 0.82, blue: 0.92)
    static let violet = Color(red: 0.55, green: 0.42, blue: 0.96)
    static let warning = Color(red: 1.00, green: 0.66, blue: 0.18)
    static let good = Color(red: 0.22, green: 0.84, blue: 0.57)
    static let ink = Color(red: 0.055, green: 0.065, blue: 0.09)
}

struct AmbientBackground: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            RadialGradient(
                colors: [R3Theme.accent.opacity(0.18), .clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 520
            )

            RadialGradient(
                colors: [R3Theme.cyan.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 500
            )

            LinearGradient(
                colors: [.white.opacity(0.025), .clear, .black.opacity(0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder
    func r3Glass(cornerRadius: CGFloat = 24, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint {
                self.glassEffect(
                    .regular.tint(tint.opacity(0.16)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            } else {
                self.glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
            }
        } else {
            self
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.20), .white.opacity(0.035)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .shadow(color: .black.opacity(0.10), radius: 24, y: 12)
        }
    }

    @ViewBuilder
    func r3ProminentButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }
}

struct PageHeader: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let symbol: String
    var trailingText: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(R3Theme.accent.opacity(0.14))
                Image(systemName: symbol)
                    .font(.system(size: 23, weight: .semibold))
                    .foregroundStyle(R3Theme.accent)
            }
            .frame(width: 56, height: 56)
            .r3Glass(cornerRadius: 17, tint: R3Theme.accent)

            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow.uppercased())
                    .font(.caption2.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(R3Theme.accent)
                Text(title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if let trailingText {
                StatusPill(text: trailingText, tint: R3Theme.good)
            }
        }
    }
}

struct GlassSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    let tint: Color?
    let content: Content

    init(
        _ title: String,
        subtitle: String? = nil,
        symbol: String? = nil,
        tint: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 11) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(tint ?? R3Theme.accent)
                        .frame(width: 30, height: 30)
                        .background((tint ?? R3Theme.accent).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let subtitle {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            content
        }
        .padding(20)
        .r3Glass(cornerRadius: 24, tint: tint)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let detail: String
    let symbol: String
    var tint: Color = R3Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 36, height: 36)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: tint.opacity(0.7), radius: 7)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(title)
                    .font(.subheadline.weight(.medium))
            }

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 166, alignment: .leading)
        .r3Glass(cornerRadius: 24, tint: tint)
    }
}

struct StatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .shadow(color: tint.opacity(0.8), radius: 5)
            Text(text)
                .lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .r3Glass(cornerRadius: 999, tint: tint)
    }
}

struct RingProgress: View {
    let value: Double
    let tint: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.075), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(value, 0), 1))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.55), tint], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: tint.opacity(0.28), radius: 8)
        }
    }
}

extension UInt64 {
    var storageText: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .memory)
    }
}
