import CoreData
import SwiftDate
import SwiftUI
import UIKit

struct LoopView: View {
    @Environment(\.colorScheme) var colorScheme

    private enum Config {
        static let lag: TimeInterval = 30
    }

    var dosingMode: DosingMode = .closed
    let closedLoop: Bool
    let timerDate: Date
    let isLooping: Bool
    let lastLoopDate: Date
    let manualTempBasal: Bool

    let determination: [OrefDetermination]

    private let rect = CGRect(x: 0, y: 0, width: 18, height: 18)

    var body: some View {
        loopStatusWithMinutes
            .padding(.vertical, 5)
            .padding(.horizontal, 10)
        /* .overlay(
             Capsule()
                 .stroke(color.opacity(0.4), lineWidth: 1)
         ) */
    }

    private var loopStatusWithMinutes: some View {
        HStack(alignment: .center) {
            ZStack {
                if let symbol = HomeDosingStatus.symbol(for: dosingMode) {
                    Image(systemName: symbol)
                        .accessibilityLabel(Text(dosingMode.title))
                } else {
                    let circle = (!closedLoop || manualTempBasal) ? "circle.dotted" : "circle"
                    Image(systemName: circle)
                    Image(systemName: circle)
                        .scaleEffect(0.85)
                }

                if isLooping {
                    ProgressView()
                }
            }

            if isLooping {
                Text("looping")
            } else if manualTempBasal {
                Text("Manual")
            } else if determination.first?.deliverAt != nil {
                // previously the .timestamp property was used here because this only gets updated
                // when the reportenacted function in the aps manager gets called
                Text(timeString)
            } else {
                Text("--")
            }
        }

        .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded)
        .foregroundColor(color)
    }

    private var timeString: String {
        let minAgo = Int((timerDate.timeIntervalSince(lastLoopDate) - Config.lag) / 60) + 1
        if minAgo > 1440 {
            return "--"
        }
        return "\(minAgo) " + NSLocalizedString("min", comment: "Minutes ago since last loop")
    }

    private var color: Color {
        guard determination.first?.timestamp != nil
        else {
            // previously the .timestamp property was used here because this only gets updated when the reportenacted function in the aps manager gets called
            return .secondary
        }
        guard manualTempBasal == false else {
            return .loopManualTemp
        }
        guard dosingMode.allowsAutomation else {
            return .secondary
        }

        let delta = timerDate.timeIntervalSince(lastLoopDate) - Config.lag

        if delta <= 5.minutes.timeInterval {
            guard determination.first?.timestamp != nil else {
                return .loopYellow
            }
            return .loopGreen
        } else if delta <= 10.minutes.timeInterval {
            return .loopYellow
        } else {
            return .loopRed
        }
    }
}

extension View {
    func animateForever(
        using animation: Animation = Animation.easeInOut(duration: 1),
        autoreverses: Bool = false,
        _ action: @escaping () -> Void
    ) -> some View {
        let repeated = animation.repeatForever(autoreverses: autoreverses)

        return onAppear {
            withAnimation(repeated) {
                action()
            }
        }
    }
}

enum HomeDosingStatus {
    static func symbol(for mode: DosingMode) -> String? {
        switch mode {
        case .closed: return "circle"
        case .open: return "pause.circle"
        case .lowGlucoseSuspend: return "hand.raised.circle"
        case .basalTesting: return "waveform.circle"
        }
    }

    static func detail(for mode: DosingMode, closedLoopAdjustment: String?) -> String {
        switch mode {
        case .closed: return closedLoopAdjustment ?? "Normal profil: 100 %"
        case .open: return "Visar dosförslag utan automatisk dosering."
        case .lowGlucoseSuspend: return "Kan sänka eller pausa basalen. Korrigerar inte höga värden."
        case .basalTesting: return "Följer basalprofilen. Kan pausa vid lågt eller förväntat lågt glukos."
        }
    }
}
