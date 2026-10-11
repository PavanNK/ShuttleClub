import SwiftUI

struct SenseGripSetup: View {
    @Environment(GameModel.self) private var game
    @State private var adjustment: Adjustment = .position
    var onBack: @MainActor () -> Void

    private enum Adjustment: String, CaseIterable, Identifiable {
        case position = "Position", angle = "Angle"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: onBack) { Label("Back to setup", systemImage: "chevron.left") }
                .font(.subheadline.bold()).buttonStyle(.plain)
            HStack(alignment: .firstTextBaseline) {
                Text("Fit your racket").font(.system(size: 30, weight: .heavy, design: .rounded))
                Spacer()
                ClubPill(title: game.leftHand ? "LEFT HAND" : "RIGHT HAND")
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 16) {
                    UprightRacketGuide()
                    Text("Hold the controller in a comfortable ready pose, with your hand in front of you. Align makes the racket stand upright from that pose.")
                        .font(.subheadline).foregroundStyle(Color.clubInk.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Align angle") { game.setGrip() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!game.canAdjustControllerGrip)
                    .accessibilityIdentifier("alignControllerRacket")
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white, in: RoundedRectangle(cornerRadius: 18))

            HStack(spacing: 12) {
                ForEach(Adjustment.allCases) { choice in
                    Button { adjustment = choice } label: {
                        Text(choice.rawValue)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .foregroundStyle(adjustment == choice ? Color.white : Color.clubInk)
                            .background(adjustment == choice ? Color.clubViolet : Color.white,
                                        in: RoundedRectangle(cornerRadius: 15))
                    }.buttonStyle(.plain)
                        .accessibilityAddTraits(adjustment == choice ? .isSelected : [])
                        .accessibilityIdentifier(choice == .position ? "controllerFitPosition" : "controllerFitAngle")
                }
            }

            VStack(spacing: 18) {
                if adjustment == .position {
                    fitSlider("Along grip", keyPath: \.translation.y, range: -0.08...0.08, step: 0.001,
                              centimetres: true, identifier: "controllerFitHandle")
                    fitSlider("Side to side", keyPath: \.translation.x, range: -0.08...0.08, step: 0.001,
                              centimetres: true, identifier: "controllerFitSide")
                    fitSlider("Forward & back", keyPath: \.translation.z, range: -0.08...0.08, step: 0.001,
                              centimetres: true, identifier: "controllerFitDepth")
                } else {
                    fitSlider("Front/back tilt", keyPath: \.pitchDegrees, range: -90...90, step: 1,
                              identifier: "controllerFitPitch")
                    fitSlider("Twist", keyPath: \.yawDegrees, range: -90...90, step: 1,
                              identifier: "controllerFitYaw")
                    fitSlider("Side tilt", keyPath: \.rollDegrees, range: -90...90, step: 1,
                              identifier: "controllerFitRoll")
                }
            }.padding(18).background(.white, in: RoundedRectangle(cornerRadius: 18))
                .disabled(!game.canAdjustControllerGrip)
            if adjustment == .position { Text("Position adjustments follow your controller grip.").font(.caption).foregroundStyle(.secondary) }

            HStack {
                Button("Reset fit") { game.resetControllerGrip() }
                    .buttonStyle(.bordered).disabled(!game.canAdjustControllerGrip)
                    .accessibilityIdentifier("resetControllerRacketFit")
                Spacer()
                Text("Changes save automatically.\nSeparate fits for left and right.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            if !game.canAdjustControllerGrip {
                Text(game.controllerReady ? "Pause play to adjust your fit." : "Keep your selected controller in view to adjust the fit.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(30).frame(width: 540)
            .foregroundStyle(Color.clubInk).tint(.clubViolet)
            .background(Color.clubPaper, in: RoundedRectangle(cornerRadius: 26))
    }

    private func fitBinding(_ keyPath: WritableKeyPath<SenseGripFit, Float>) -> Binding<Float> {
        Binding(get: { game.controllerGripFit[keyPath: keyPath] }, set: { value in
            guard game.canAdjustControllerGrip else { return }
            var fit = game.controllerGripFit
            fit[keyPath: keyPath] = value
            game.setControllerGripFit(fit.normalized())
        })
    }

    private func fitSlider(_ title: String, keyPath: WritableKeyPath<SenseGripFit, Float>,
                           range: ClosedRange<Float>, step: Float, centimetres: Bool = false,
                           identifier: String) -> some View {
        let binding = fitBinding(keyPath)
        return VStack(spacing: 5) {
            HStack {
                Text(title).font(.subheadline.bold())
                Spacer()
                Text(centimetres ? String(format: "%+.1f cm", Double(binding.wrappedValue * 100))
                                : String(format: "%+.0f°", Double(binding.wrappedValue)))
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: binding, in: range, step: step) { Text(title) }
                .accessibilityIdentifier(identifier)
        }
    }
}

private struct UprightRacketGuide: View {
    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let centre = size.width / 2
                let head = CGRect(x: size.width * 0.19, y: 4,
                                  width: size.width * 0.62, height: size.height * 0.47)
                let bed = Path(ellipseIn: head.insetBy(dx: 3, dy: 3))
                var strings = context
                strings.clip(to: bed)
                var grid = Path()
                for index in 1..<6 {
                    let x = head.minX + head.width * CGFloat(index) / 6
                    grid.move(to: CGPoint(x: x, y: head.minY))
                    grid.addLine(to: CGPoint(x: x, y: head.maxY))
                    let y = head.minY + head.height * CGFloat(index) / 6
                    grid.move(to: CGPoint(x: head.minX, y: y))
                    grid.addLine(to: CGPoint(x: head.maxX, y: y))
                }
                strings.stroke(grid, with: .color(Color.clubInk.opacity(0.35)), lineWidth: 0.8)
                context.stroke(Path(ellipseIn: head), with: .color(.clubCoral), lineWidth: 3)
                var shaft = Path()
                shaft.move(to: CGPoint(x: centre, y: head.maxY))
                shaft.addLine(to: CGPoint(x: centre, y: size.height - 5))
                context.stroke(shaft, with: .color(.clubViolet), lineWidth: 3)
                let grip = CGRect(x: centre - 4, y: size.height * 0.76,
                                  width: 8, height: size.height * 0.21)
                context.fill(Path(roundedRect: grip, cornerRadius: 3), with: .color(.clubViolet))
            }.frame(width: 62, height: 90)
            Text("UPRIGHT").font(.system(size: 9, weight: .heavy, design: .rounded)).tracking(0.8)
                .foregroundStyle(Color.clubViolet)
        }.padding(9).background(Color.clubMint.opacity(0.10), in: RoundedRectangle(cornerRadius: 15))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Upright racket alignment target")
    }
}
