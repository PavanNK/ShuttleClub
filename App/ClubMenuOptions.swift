import SwiftUI

enum ClubMenuDesignStyle: String, CaseIterable {
    case sunny, playful, sport

    var title: String {
        switch self {
        case .sunny: "Sunny club"
        case .playful: "Playful mint"
        case .sport: "Sport glass"
        }
    }
}

struct ClubMenuOption: View {
    let style: ClubMenuDesignStyle
    var onPlay: () -> Void = {}
    var onRacket: () -> Void = {}
    var onMode: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        Group {
            switch style {
            case .sunny: sunny
            case .playful: playful
            case .sport: sport
            }
        }.buttonStyle(MenuOptionPress())
            .accessibilityElement(children: .contain)
    }

    private var sunny: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Label("Come play", systemImage: "sun.max.fill")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MenuPalette.coral)
                Spacer()
                settingsButton(tint: MenuPalette.ink, background: .white.opacity(0.8))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Shuttle\nClub").font(.system(size: 49, weight: .black, design: .rounded))
                        .tracking(-1.6).lineSpacing(-5)
                    Text("Your next rally starts here.")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundStyle(MenuPalette.ink.opacity(0.65))
                }
                Spacer(minLength: 0)
                Image(systemName: "figure.badminton")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(MenuPalette.coral)
                    .frame(width: 95, height: 115)
                    .background(MenuPalette.yellow.opacity(0.55), in: RoundedRectangle(cornerRadius: 36))
                    .rotationEffect(.degrees(-7))
                    .accessibilityHidden(true)
            }
            Spacer(minLength: 5)
            playButton(fill: MenuPalette.yellow, tint: MenuPalette.ink, corner: 22)
                .shadow(color: MenuPalette.coral.opacity(0.20), radius: 0, y: 5)
            HStack(spacing: 12) {
                sunnyTile("Racket", symbol: "tennis.racket", tint: MenuPalette.coral, action: onRacket)
                sunnyTile("Game mode", symbol: "square.grid.2x2.fill", tint: MenuPalette.violet, action: onMode)
            }
        }.padding(28).frame(width: 446, height: 540)
            .foregroundStyle(MenuPalette.ink)
            .background(MenuPalette.cream, in: RoundedRectangle(cornerRadius: 34))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.9), lineWidth: 1.5).allowsHitTesting(false))
            .shadow(color: MenuPalette.ink.opacity(0.12), radius: 18, y: 9)
    }

    private var playful: some View {
        VStack(spacing: 18) {
            HStack {
                Text("Let’s rally").font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MenuPalette.violet)
                Spacer()
                settingsButton(tint: MenuPalette.violet, background: .white.opacity(0.65))
            }
            ZStack {
                Circle().fill(.white.opacity(0.65)).frame(width: 94, height: 94)
                Image(systemName: "figure.badminton").font(.system(size: 47, weight: .bold))
                    .foregroundStyle(MenuPalette.violet).rotationEffect(.degrees(7))
                Image(systemName: "sparkle").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(MenuPalette.coral).offset(x: 65, y: -18)
                Circle().fill(MenuPalette.yellow).frame(width: 12, height: 12).offset(x: -60, y: 26)
            }.accessibilityHidden(true)
            Text("Shuttle Club").font(.system(size: 42, weight: .black, design: .rounded))
                .tracking(-1.4).foregroundStyle(MenuPalette.violet)
            Text("Ready for a rally?").font(.system(size: 17, weight: .medium, design: .rounded))
                .foregroundStyle(MenuPalette.ink.opacity(0.7))
            Spacer(minLength: 0)
            playButton(fill: MenuPalette.violet, tint: .white, corner: 34)
                .shadow(color: MenuPalette.violet.opacity(0.20), radius: 0, y: 5)
            HStack(spacing: 10) {
                playfulPill("Racket", symbol: "tennis.racket", action: onRacket)
                playfulPill("Game mode", symbol: "square.grid.2x2.fill", action: onMode)
            }
        }.padding(28).frame(width: 446, height: 560)
            .background(MenuPalette.mint, in: RoundedRectangle(cornerRadius: 42))
            .overlay(RoundedRectangle(cornerRadius: 42).stroke(.white.opacity(0.65), lineWidth: 2).allowsHitTesting(false))
            .shadow(color: MenuPalette.violet.opacity(0.12), radius: 18, y: 9)
    }

    private var sport: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Shuttle Club", systemImage: "figure.badminton")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                settingsButton(tint: .white, background: .white.opacity(0.10))
            }
            Rectangle().fill(.white.opacity(0.16)).frame(height: 1).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("Meet you\non court.")
                    .font(.system(size: 43, weight: .semibold)).tracking(-1.2).lineSpacing(-3)
                    .foregroundStyle(.white)
                Text("A rally with Milo.").font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.60))
            }.padding(.top, 6)
            Spacer(minLength: 6)
            playButton(fill: MenuPalette.coral, tint: .white, corner: 17)
            VStack(spacing: 0) {
                sportRow("Racket", symbol: "tennis.racket", action: onRacket)
                Rectangle().fill(.white.opacity(0.10)).frame(height: 1).padding(.horizontal, 16).accessibilityHidden(true)
                sportRow("Game mode", symbol: "square.grid.2x2", action: onMode)
            }.background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18))
        }.padding(28).frame(width: 446, height: 540)
            .background(MenuPalette.smoke, in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(.white.opacity(0.21), lineWidth: 1).allowsHitTesting(false))
            .shadow(color: MenuPalette.smoke.opacity(0.25), radius: 22, y: 12)
    }

    private func playButton(fill: Color, tint: Color, corner: CGFloat) -> some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                Image(systemName: "play.fill").font(.system(size: 18, weight: .bold))
                Text("Play with Milo").font(.system(size: 24, weight: .bold, design: .rounded))
                Spacer(minLength: 4)
                Image(systemName: "arrow.right").font(.system(size: 18, weight: .semibold))
            }.padding(.horizontal, 21).frame(height: 72)
                .foregroundStyle(tint).background(fill, in: RoundedRectangle(cornerRadius: corner))
        }.accessibilityIdentifier("menu.\(style.rawValue).play")
    }

    private func settingsButton(tint: Color, background: Color) -> some View {
        Button(action: onSettings) {
            Image(systemName: "gearshape").font(.system(size: 20, weight: .semibold))
                .frame(width: 44, height: 44).foregroundStyle(tint).background(background, in: Circle())
        }.accessibilityLabel("Settings").accessibilityIdentifier("menu.\(style.rawValue).settings")
    }

    private func sunnyTile(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol).font(.system(size: 23, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(MenuPalette.ink)
            }.frame(maxWidth: .infinity).frame(height: 82).background(.white, in: RoundedRectangle(cornerRadius: 22))
        }
    }

    private func playfulPill(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol).font(.system(size: 18, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 55).foregroundStyle(MenuPalette.violet)
                .background(.white.opacity(0.75), in: Capsule())
        }
    }

    private func sportRow(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol).font(.system(size: 18, weight: .medium)).frame(width: 23)
                Text(title).font(.system(size: 18, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
            }.padding(.horizontal, 17).frame(height: 53).foregroundStyle(.white.opacity(0.9))
        }
    }
}

private enum MenuPalette {
    static let cream = Color(red: 1, green: 0.965, blue: 0.89)
    static let yellow = Color(red: 1, green: 0.79, blue: 0.24)
    static let coral = Color(red: 0.98, green: 0.34, blue: 0.36)
    static let mint = Color(red: 0.64, green: 0.94, blue: 0.82)
    static let violet = Color(red: 0.34, green: 0.18, blue: 0.64)
    static let ink = Color(red: 0.13, green: 0.19, blue: 0.20)
    static let smoke = Color(red: 0.15, green: 0.10, blue: 0.23)
}

private struct MenuOptionPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.23, dampingFraction: 0.78), value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}
