import AudioToolbox
import SwiftUI
import Swinject

extension Snooze {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State private var selectedInterval = 1

        private var pickerTimes: [TimeInterval] {
            [0] + stride(from: 15, through: 180, by: 15).map { TimeInterval(minutes: Double($0)) } +
                (4 ... 8).map { TimeInterval(hours: Double($0)) }
        }

        private var formatter: DateComponentsFormatter {
            let formatter = DateComponentsFormatter()
            formatter.allowsFractionalUnits = false
            formatter.allowedUnits = [.hour, .minute]
            formatter.unitsStyle = .short
            return formatter
        }

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            return formatter
        }

        private func formatInterval(_ interval: TimeInterval) -> String {
            formatter.string(from: interval)!
        }

        private var alarmDescription: String {
            switch state.alarm {
            case .high:
                return NSLocalizedString("High Glucose Alarm active", comment: "High Glucose Alarm active")
            case .low:
                return NSLocalizedString("Low Glucose Alarm active", comment: "Low Glucose Alarm active")
            case .none:
                return NSLocalizedString("No Glucose Alarm active", comment: "No Glucose Alarm active")
            }
        }

        private var snoozeDescription: String {
            if state.snoozeUntilDate > Date() {
                return String(
                    format: NSLocalizedString("snoozing until %@", comment: "snoozing until %@"),
                    dateFormatter.string(from: state.snoozeUntilDate)
                )
            }
            return NSLocalizedString("not snoozing", comment: "not snoozing")
        }

        private var snoozeButton: some View {
            Button {
                let interval = pickerTimes[selectedInterval]
                let snoozeFor = formatInterval(interval)
                let untilDate = Date() + interval
                state.snoozeUntilDate = interval > 0 ? untilDate : .distantPast
                debug(.default, "will snooze for \(snoozeFor) until \(dateFormatter.string(from: untilDate))")
                if interval > 0 {
                    BaseUserNotificationsManager.stopSound()
                }
                state.hideModal()
            } label: {
                Text(selectedInterval == 0 ? "Cancel Snooze" : "Click to Snooze Alerts")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Color(.systemBlue), in: Capsule())
            }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowSeparator(.hidden)
        }

        private var snoozePicker: some View {
            VStack {
                Picker(selection: $selectedInterval, label: Text("Snooze duration")) {
                    ForEach(0 ..< pickerTimes.count) {
                        if $0 == 0 {
                            Text("Cancel Snooze")
                                .tag($0)
                        } else {
                            Text(formatInterval(self.pickerTimes[$0]))
                                .tag($0)
                        }
                    }
                }
                .pickerStyle(.wheel)
            }
        }

        var body: some View {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if state.alarm != nil {
                                Image(systemName: "alarm.waves.left.and.right")
                                    .accessibilityHidden(true)
                            }
                            Text(alarmDescription)
                        }
                        Text(snoozeDescription)
                            .foregroundStyle(.secondary)
                    }
                    .lineLimit(nil)
                    snoozePicker
                }
                .listRowBackground(Color.chart)

                Section {
                    snoozeButton
                }
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationBarTitle("Snooze Alerts")
            .navigationBarTitleDisplayMode(.automatic)
            .navigationBarItems(trailing: Button("Close", action: state.hideModal))
            .onAppear {
                configureView()
            }
        }
    }
}

extension TimeInterval {
    static func seconds(_ seconds: Double) -> TimeInterval {
        seconds
    }

    static func minutes(_ minutes: Double) -> TimeInterval {
        TimeInterval(minutes: minutes)
    }

    static func hours(_ hours: Double) -> TimeInterval {
        TimeInterval(hours: hours)
    }

    init(minutes: Double) {
        // self.init(minutes * 60)
        let m = minutes * 60
        self.init(m)
    }

    init(hours: Double) {
        self.init(minutes: hours * 60)
    }

    var minutes: Double {
        self / 60.0
    }

    var hours: Double {
        minutes / 60.0
    }
}
