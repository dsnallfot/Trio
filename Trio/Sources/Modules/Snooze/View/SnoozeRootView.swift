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
                return NSLocalizedString("High glucose", comment: "Short current alarm label")
            case .low:
                return NSLocalizedString("Low glucose", comment: "Short current alarm label")
            case .urgentHigh:
                return NSLocalizedString("Urgent high glucose", comment: "Short current alarm label")
            case .urgentLow:
                return NSLocalizedString("Urgent low glucose", comment: "Short current alarm label")
            case .none:
                return NSLocalizedString("No Glucose Alarm active", comment: "No Glucose Alarm active")
            }
        }

        private func alarmRow(_ description: String, snoozeUntil: Date) -> some View {
            let isSnoozed = snoozeUntil > state.now
            let status = isSnoozed ? snoozedUntilDescription(snoozeUntil) :
                NSLocalizedString("Not snoozed", comment: "Current alarm has no active snooze")
            let suffix = " – " + status
            return HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: isSnoozed ? "moon.zzz.fill" : "alarm.waves.left.and.right")
                    .foregroundStyle(isSnoozed ? Color.secondary : Color.primary)
                    .accessibilityHidden(true)
                Text("\(Text(description))\(Text(suffix).foregroundColor(.secondary))")
            }
        }

        private func snoozedUntilDescription(_ date: Date) -> String {
            String(
                format: NSLocalizedString("Snoozed until %@", comment: "Individual alarm snooze deadline"),
                dateFormatter.string(from: date)
            )
        }

        private var snoozeDescription: String {
            if state.snoozeUntilDate > state.now {
                return String(
                    format: NSLocalizedString("All alarms snoozed until %@", comment: "Shared snooze deadline"),
                    dateFormatter.string(from: state.snoozeUntilDate)
                )
            }
            return NSLocalizedString("No shared snooze", comment: "No global pause; individual alarms may still be snoozed")
        }

        private var snoozeButton: some View {
            Button {
                let interval = pickerTimes[selectedInterval]
                let snoozeFor = formatInterval(interval)
                let untilDate = Date() + interval
                debug(.default, "will snooze for \(snoozeFor) until \(dateFormatter.string(from: untilDate))")
                if interval > 0 {
                    state.snoozeUntilDate = untilDate
                    BaseUserNotificationsManager.stopSound()
                } else {
                    state.cancelSnoozes()
                }
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
            VStack(alignment: .leading) {
                Picker(selection: $selectedInterval, label: Text("Snooze duration")) {
                    ForEach(0 ..< pickerTimes.count, id: \.self) {
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
                        if state.alarm != nil {
                            alarmRow(alarmDescription, snoozeUntil: state.alarmSnoozeUntil)
                        }
                        if state.missedLoop {
                            alarmRow(
                                NSLocalizedString("Missed loop", comment: "Short current alarm label"),
                                snoozeUntil: state.snoozeUntilDate
                            )
                        }
                        if state.missedReadings {
                            alarmRow(
                                NSLocalizedString("Missing readings", comment: "Short current alarm label"),
                                snoozeUntil: state.snoozeUntilDate
                            )
                        }
                        if state.alarm == nil, !state.missedLoop, !state.missedReadings {
                            Text(alarmDescription)
                        }
                    }
                    .lineLimit(nil)
                } header: {
                    Text("Active alarms")
                }
                .listRowBackground(Color.chart)

                Section {
                    Text(snoozeDescription)
                        .foregroundStyle(.secondary)
                    snoozePicker
                } header: {
                    Text("Snooze all alarms & notifications")
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
            .task {
                await state.observePresentation()
            }
            .task {
                await state.observeMissingAlarms()
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
