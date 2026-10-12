import SwiftUI

/// The same grip feedback appears in setup and beside the live court.
struct RacketTrackingStatus: View {
    @Environment(GameModel.self) private var game
    var compact = false

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 10 : 14) {
            Image(systemName: symbol)
                .font(.system(size: compact ? 18 : 23, weight: .semibold))
                .foregroundStyle(ready ? Color.clubMint : Color.clubViolet)
                .frame(width: compact ? 25 : 32, height: compact ? 25 : 32)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: compact ? 14 : 18, weight: .bold, design: .rounded))
                Text(detail).font(.system(size: compact ? 12 : 15))
                    .foregroundStyle(Color.clubInk.opacity(0.70))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.foregroundStyle(Color.clubInk)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("racketTrackingStatus")
    }

    private var ready: Bool { game.racketReady }
    private var selectedHand: String { game.leftHand ? "Left" : "Right" }
    private var symbol: String {
        if ready { return "checkmark.circle.fill" }
        if game.input == .sense { return "gamecontroller.fill" }
        return game.handGripLocked ? "hand.raised.fill" : "hand.raised"
    }
    private var title: String {
        if game.input == .sense { return ready ? "\(selectedHand) controller ready" : "Connect your \(selectedHand.lowercased()) controller" }
        if ready { return "\(selectedHand) racket held" }
        if game.handGripLocked { return "Grip kept · show your wrist" }
        if game.handAcquisitionReady { return "Close your \(selectedHand.lowercased()) hand to grab" }
        return "Show your \(selectedHand.lowercased()) palm"
    }
    private var detail: String {
        if ready {
            let panelOpen=game.showPlaySetup || game.showCourtMenu || game.showRackets || game.showSettings
            if game.paused { return panelOpen ? "Tracking is ready. Return to court, then Resume." : "Tracking is ready. Resume when you're comfortable." }
            if panelOpen { return "Tracking is ready. Return to court to play." }
            if game.canServe,game.automaticServing { return "Racket ready. Milo serves after two ready seconds." }
            return game.input == .hands ? "Grip locked. Relax your fingers and swing." : "Ready to swing. Menu pauses play."
        }
        if !game.trackingMessage.isEmpty { return game.trackingMessage }
        if game.input == .sense { return "Pair it in Vision Pro Bluetooth settings, then keep it in view." }
        if game.handGripLocked { return "Bring your selected wrist into view to recover the racket." }
        return game.handAcquisitionReady ? "Close gently, then keep a relaxed grip." : "Keep your palm and knuckles in view, then open and close to grab."
    }
}
