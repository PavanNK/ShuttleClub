import SwiftUI

enum ClubHomeStyle: String, CaseIterable, Identifiable {
    case minimal, playful
    var id: Self { self }
    var title: String { self == .minimal ? "Minimal" : "Playful" }
}

/// The approved minimal home keeps the court visible around its controls.
struct ClubHeroMenu: View {
    var modeTitle = "Free play"
    var opening = false
    var onPlay: () -> Void = {}
    var onRacket: () -> Void = {}
    var onMode: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(spacing: 18) {
            Button(action: onPlay) {
                HStack(spacing: 13) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 19, weight: .bold))
                    Text(opening ? "Getting ready…" : "Play with Milo")
                        .font(.system(size: 27, weight: .heavy, design: .rounded))
                }.frame(width: 326, height: 88)
                    .foregroundStyle(HeroPalette.paper)
                    .background(LinearGradient(colors: [HeroPalette.coral, HeroPalette.coralDeep],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 29))
                    .overlay(RoundedRectangle(cornerRadius: 29).stroke(.white.opacity(0.42), lineWidth: 1.2).allowsHitTesting(false))
                    .shadow(color: HeroPalette.coralDeep.opacity(0.28), radius: 0, y: 5)
            }.disabled(opening).accessibilityIdentifier("enterCourt")

            HStack(spacing: 14) {
            Button(action: onRacket) {
                HStack(spacing: 12) {
                    HeroRacketGlyph().frame(width: 31, height: 45)
                    Text("Racket").font(.system(size: 21, weight: .bold, design: .rounded))
                }.frame(width: 154, height: 60)
                    .modifier(HeroPaperControl(corner: 22))
            }.accessibilityIdentifier("heroMenuRacket")

            Button(action: onMode) {
                HStack(spacing: 11) {
                    HeroCourtGlyph().frame(width: 29, height: 32)
                    Text(modeTitle).font(.system(size: 19, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.85)
                }.frame(width: 177, height: 60)
                    .modifier(HeroPaperControl(corner: 22))
            }.accessibilityLabel("Choose game mode, \(modeTitle)").accessibilityIdentifier("heroMenuMode")

            Button(action: onSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 60, height: 60)
                    .modifier(HeroPaperControl(corner: 22))
            }.accessibilityLabel("Settings").accessibilityIdentifier("heroMenuSettings")
            }
        }.padding(10).frame(width: 455, height: 190)
            .buttonStyle(HeroMenuPress())
            .accessibilityElement(children: .contain)
    }
}

struct ClubHeroWordmark: View {
    var body: some View {
        VStack(spacing: 12) {
        HStack(spacing: 15) {
            HeroShuttleGlyph().frame(width: 30, height: 42)
                .rotationEffect(.degrees(-13))
                .frame(width: 55, height: 62)
                .accessibilityHidden(true)
            Text("Shuttle Club")
                .font(.system(size: 49, weight: .black, design: .rounded))
                .tracking(-1.7)
                .foregroundStyle(HeroPalette.ink)
                .shadow(color: HeroPalette.paper.opacity(0.9), radius: 0, y: 2)
                .fixedSize()
        }.padding(.horizontal, 31).frame(height: 94)
            .background(HeroPalette.paper, in: RoundedRectangle(cornerRadius: 34))
            .overlay(RoundedRectangle(cornerRadius: 34).stroke(.white.opacity(0.8), lineWidth: 1.2))
            .shadow(color: HeroPalette.ink.opacity(0.16), radius: 12, y: 5)
        Text("Good swings. Happy rallies.")
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(HeroPalette.paper)
            .shadow(color: HeroPalette.ink.opacity(0.7), radius: 4, y: 2)
        }.frame(width: 535, height: 140)
            .accessibilityElement(children: .combine)
    }
}

struct ClubPosterMenu: View {
    var modeTitle = "Free play"
    var opening = false
    var onPlay: () -> Void = {}
    var onRacket: () -> Void = {}
    var onMode: () -> Void = {}
    var onSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing:12) {
                Rectangle().frame(width:26,height:2)
                Text("A LITTLE RALLY. A LOT OF FUN.")
                    .font(.system(size: 13, weight: .heavy, design: .rounded)).tracking(1.6)
            }.foregroundStyle(Color(red: 1, green: 0.85, blue: 0.44))
            Text("Shuttle\nClub")
                .font(.system(size: 94, weight: .black, design: .rounded)).tracking(-3.6)
                .lineSpacing(-28).foregroundStyle(HeroPalette.paper)
                .shadow(color: HeroPalette.violet, radius: 0, x: 3, y: 4)
            Text("Your next great rally starts here.")
                .font(.system(size: 19, weight: .medium, design: .rounded)).foregroundStyle(HeroPalette.paper).padding(.bottom,19)
            Button(action: onPlay) {
                HStack(spacing: 16) {
                    Image(systemName: "play.fill").font(.system(size: 20))
                    Text(opening ? "Getting ready…" : "Let’s play").font(.system(size: 25, weight: .heavy, design: .rounded))
                    Spacer(); Image(systemName: "arrow.right").font(.system(size: 23))
                }.padding(.horizontal, 25).frame(width: 320, height: 80)
                    .foregroundStyle(HeroPalette.ink)
                    .background(Color(red: 1, green: 0.85, blue: 0.44), in: RoundedRectangle(cornerRadius: 26))
                    .shadow(color: Color(red: 0.68, green: 0.37, blue: 0.19), radius: 0, y: 5)
            }.disabled(opening).accessibilityIdentifier("enterCourt")
            HStack(spacing: 14) {
                Button(action: onRacket) {
                    HStack(spacing:12) { HeroRacketGlyph().frame(width:25,height:36);Text("Racket").font(.system(size: 20, weight: .bold, design: .rounded)) }
                        .frame(width: 157, height: 60).modifier(HeroPaperControl(corner: 22))
                }.accessibilityIdentifier("heroMenuRacket")
                Button(action: onMode) {
                    HStack(spacing: 10) { HeroCourtGlyph().frame(width: 24, height: 27); Text(modeTitle).font(.system(size: 18, weight: .bold, design: .rounded)).lineLimit(1).minimumScaleFactor(0.85) }
                        .frame(width: 176, height: 60).modifier(HeroPaperControl(corner: 22))
                }.accessibilityLabel("Choose game mode, \(modeTitle)").accessibilityIdentifier("heroMenuMode")
            }
        }.padding(27).frame(width: 535)
            .buttonStyle(HeroMenuPress())
    }
}

struct ClubWelcomeWordmark:View {
    var body:some View {
        HStack(spacing:16) {
            HeroShuttleGlyph(colour:HeroPalette.violet).frame(width:30,height:40)
            Text("WELCOME TO THE CLUB").font(.system(size:19,weight:.black,design:.rounded)).tracking(1.4)
        }.foregroundStyle(HeroPalette.ink).frame(width:400,height:114)
            .background(HeroPalette.paper,in:RoundedRectangle(cornerRadius:34))
    }
}

struct ClubHomeGear:View {
    var onSettings:()->Void
    var body:some View {
        Button(action:onSettings) {
            Image(systemName:"gearshape").font(.system(size:23,weight:.medium))
                .frame(width:60,height:60).modifier(HeroPaperControl(corner:22))
        }.accessibilityLabel("Settings").accessibilityIdentifier("heroMenuSettings").buttonStyle(HeroMenuPress())
    }
}

private struct HeroPaperControl: ViewModifier {
    let corner: CGFloat
    func body(content: Content) -> some View {
        content.foregroundStyle(HeroPalette.ink)
            .background(HeroPalette.paper.opacity(0.98), in: RoundedRectangle(cornerRadius: corner))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner))
            .overlay(RoundedRectangle(cornerRadius: corner).stroke(.white.opacity(0.72), lineWidth: 1.2).allowsHitTesting(false))
            .shadow(color: HeroPalette.ink.opacity(0.15), radius: 9, y: 4)
    }
}

private struct HeroRacketGlyph: View {
    var body: some View {
        Canvas { context, size in
            let oval = CGRect(x: size.width * 0.15, y: size.height * 0.04,
                              width: size.width * 0.7, height: size.height * 0.56)
            context.fill(Path(ellipseIn: oval), with: .color(HeroPalette.paper))
            var strings = context
            strings.clip(to: Path(ellipseIn: oval))
            var weave = Path()
            for line in 1..<7 {
                let x = oval.minX + oval.width * CGFloat(line) / 7
                weave.move(to: CGPoint(x: x, y: oval.minY)); weave.addLine(to: CGPoint(x: x, y: oval.maxY))
                let y = oval.minY + oval.height * CGFloat(line) / 7
                weave.move(to: CGPoint(x: oval.minX, y: y)); weave.addLine(to: CGPoint(x: oval.maxX, y: y))
            }
            strings.stroke(weave, with: .color(HeroPalette.ink.opacity(0.42)), lineWidth: 0.8)
            context.stroke(Path(ellipseIn: oval), with: .color(HeroPalette.coral), lineWidth: 2.8)
            var shaft = Path()
            shaft.move(to: CGPoint(x: size.width / 2, y: oval.maxY))
            shaft.addLine(to: CGPoint(x: size.width / 2, y: size.height * 0.93))
            context.stroke(shaft, with: .color(HeroPalette.violet), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }.rotationEffect(.degrees(-16)).accessibilityHidden(true)
    }
}

private struct HeroCourtGlyph: View {
    var body: some View {
        Canvas { context, size in
            let court = CGRect(x: 1.5, y: 2, width: size.width - 3, height: size.height - 4)
            var lines = Path(roundedRect: court, cornerRadius: 3)
            lines.move(to: CGPoint(x: court.midX, y: court.minY)); lines.addLine(to: CGPoint(x: court.midX, y: court.maxY))
            for fraction: CGFloat in [0.28, 0.72] {
                let y = court.minY + court.height * fraction
                lines.move(to: CGPoint(x: court.minX, y: y)); lines.addLine(to: CGPoint(x: court.maxX, y: y))
            }
            context.stroke(lines, with: .color(HeroPalette.violet.opacity(0.8)), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
            var net = Path()
            net.move(to: CGPoint(x: court.minX - 1, y: court.midY)); net.addLine(to: CGPoint(x: court.maxX + 1, y: court.midY))
            context.stroke(net, with: .color(HeroPalette.coral), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
        }.accessibilityHidden(true)
    }
}

private struct HeroShuttleGlyph: View {
    var colour:Color=HeroPalette.coral
    var body: some View {
        Canvas { context, size in
            let base = CGPoint(x: size.width / 2, y: size.height * 0.69)
            for feather in 0..<5 {
                let x = size.width * (0.08 + CGFloat(feather) * 0.21)
                let top = CGPoint(x: x, y: size.height * (feather == 0 || feather == 4 ? 0.14 : 0.05))
                var plume = Path()
                plume.move(to: CGPoint(x: base.x + (x - base.x) * 0.28, y: base.y))
                plume.addQuadCurve(to: top, control: CGPoint(x: x, y: size.height * 0.41))
                context.stroke(plume, with: .color(colour), style: StrokeStyle(lineWidth: 4.3, lineCap: .round))
            }
            let band = CGRect(x: size.width * 0.31, y: size.height * 0.62, width: size.width * 0.38, height: size.height * 0.13)
            context.fill(Path(roundedRect: band, cornerRadius: 2), with: .color(HeroPalette.violet))
            let cork = CGRect(x: size.width * 0.32, y: size.height * 0.74, width: size.width * 0.36, height: size.height * 0.22)
            context.fill(Path(roundedRect: cork, cornerRadius: 5), with: .color(HeroPalette.ink))
        }
    }
}

private enum HeroPalette {
    static let paper = Color(red: 1, green: 0.97, blue: 0.89)
    static let ink = Color(red: 0.10, green: 0.20, blue: 0.23)
    static let coral = Color(red: 1, green: 0.34, blue: 0.39)
    static let coralDeep = Color(red: 0.92, green: 0.22, blue: 0.30)
    static let violet = Color(red: 0.37, green: 0.21, blue: 0.66)
}

private struct HeroMenuPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.80), value: configuration.isPressed)
            .hoverEffect(.lift)
    }
}
