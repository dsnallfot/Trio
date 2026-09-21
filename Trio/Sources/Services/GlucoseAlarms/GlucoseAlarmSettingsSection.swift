import SwiftUI

struct GlucoseAlarmSettingsSection: View {
    @ObservedObject private var preferences = GlucoseAlarmPreferences.shared
    @ObservedObject private var manager = TrioAlertManager.shared
    @Environment(\.scenePhase) private var scenePhase

    let low: Decimal
    let high: Decimal
    let units: GlucoseUnits

    var body: some View {
        Section {
            Toggle("Larm för akut lågt glukos", isOn: $preferences.urgentLowEnabled)
            if preferences.urgentLowEnabled {
                GlucoseAlarmThresholdPicker(
                    title: "Akut låg glukoslarmgräns", value: $preferences.urgentLowThreshold,
                    lower: 40, upper: max(40, low), units: units
                )
                tonePicker("Ljud vid akut lågt glukos", selection: $preferences.urgentLowTone)
                snoozePicker("Snooze för akut låglarm", selection: $preferences.urgentLowSnoozeMinutes)
            }
        } header: {
            Text("Lokala glukoslarm")
        }
        .listRowBackground(Color.chart)
        Section {
            Toggle("Larm för lågt glukos", isOn: $preferences.lowEnabled)
            if preferences.lowEnabled {
                tonePicker("Ljud vid lågt glukos", selection: $preferences.lowTone)
                snoozePicker("Snooze för låglarm", selection: $preferences.lowSnoozeMinutes)
            }
        }
        .listRowBackground(Color.chart)
        Section {
            Toggle("Larm för högt glukos", isOn: $preferences.highEnabled)
            if preferences.highEnabled {
                tonePicker("Ljud vid högt glukos", selection: $preferences.highTone)
                snoozePicker("Snooze för höglarm", selection: $preferences.highSnoozeMinutes)
            }
        }
        .listRowBackground(Color.chart)
        Section {
            Toggle("Larm för akut högt glukos", isOn: $preferences.urgentHighEnabled)
            if preferences.urgentHighEnabled {
                GlucoseAlarmThresholdPicker(
                    title: "Akut hög glukoslarmgräns", value: $preferences.urgentHighThreshold,
                    lower: min(400, high), upper: 400, units: units
                )
                tonePicker("Ljud vid akut högt glukos", selection: $preferences.urgentHighTone)
                snoozePicker("Snooze för akut höglarm", selection: $preferences.urgentHighSnoozeMinutes)
            }
        }
        .listRowBackground(Color.chart)
        Section {
            Toggle("Larma även vid tyst läge & Fokus", isOn: $preferences.alarmKit)
            if preferences.alarmKit {
                Toggle("Visa mer inställningar", isOn: $preferences.showMoreSettings)
                Text(manager.permissionText).font(.footnote).foregroundStyle(.secondary)
                if preferences.showMoreSettings {
                    Button("Tillåt systemlarm") { Task { await manager.requestPermission() } }
                    Button("Testa lågljud om 10 sekunder") { Task { await manager.testAlarm(tone: preferences.lowTone) } }
                    Button("Testa högljud om 10 sekunder") { Task { await manager.testAlarm(tone: preferences.highTone) } }
                    Button("Testa akut lågljud om 10 sekunder") {
                        Task { await manager.testAlarm(tone: preferences.urgentLowTone) } }
                    Button("Testa akut högljud om 10 sekunder") {
                        Task { await manager.testAlarm(tone: preferences.urgentHighTone) } }
                    if manager.testAlarmID != nil {
                        Button("Avbryt testlarm") { manager.cancelTestAlarm() }
                    }
                    Text(
                        "Testlarmet ändrar inga glukosvärden och påverkar inte loopen. Lås gärna skärmen efter att du startat testet."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    Button("Öppna iOS-inställningar") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
            }
            if !manager.notificationText.isEmpty {
                Text(manager.notificationText).font(.footnote).foregroundStyle(.orange)
            }
            if let warning = manager.thresholdWarning {
                Text(warning).font(.footnote).foregroundStyle(.red)
            }
            if let error = manager.deliveryError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text(
                "Gäller alla glukoskällor. Aktiverade akuta larm har företräde framför vanliga larm på samma sida, även under snooze. Vanlig låg/hög-snooze hindrar inte akuta larm. Utan kvittering upprepas larm vid nästa nya aktuella glukosvärde, normalt var femte minut (minst 4,5 minuter mellan upprepningar). Ett larm som löper ut startar ingen snooze. Stop pausar endast den aktuella larmtypen enligt dess snoozetid. Trios vanliga globala snooze pausar fortfarande alla fyra typerna. Utan tillåtna systemlarm används notisljud som kan tystas av iOS. Valet Glukosnotiser påverkar inte dessa larm. Informationsnotiser och kolhydratljud ställs in separat."
            )
        }
        .listRowBackground(Color.chart)
        .onDisappear { preferences.stopPreview() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { manager.updatePermission() } else { preferences.stopPreview() }
        }
        .onChange(of: preferences.lowEnabled) { _, enabled in
            if enabled && preferences.alarmKit { Task { await manager.requestPermission() } }
        }
        .onChange(of: preferences.highEnabled) { _, enabled in
            if enabled && preferences.alarmKit { Task { await manager.requestPermission() } }
        }
        .onChange(of: preferences.urgentLowEnabled) { _, enabled in
            if enabled && preferences.alarmKit { Task { await manager.requestPermission() } }
        }
        .onChange(of: preferences.urgentHighEnabled) { _, enabled in
            if enabled && preferences.alarmKit { Task { await manager.requestPermission() } }
        }
        .onChange(of: preferences.alarmKit) { _, enabled in
            if enabled &&
                (
                    preferences.lowEnabled || preferences.highEnabled || preferences.urgentLowEnabled || preferences
                        .urgentHighEnabled
                ) { Task { await manager.requestPermission() } }
        }
    }

    private func snoozePicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(GlucoseAlarmConfiguration.snoozeChoices, id: \.self) { minutes in
                Text("\(minutes) minuter").tag(minutes)
            }
        }
    }

    private func tonePicker(_ title: String, selection: Binding<GlucoseAlarmPreferences.Tone>) -> some View {
        VStack(alignment: .leading) {
            Picker(title, selection: selection) {
                ForEach(GlucoseAlarmPreferences.Tone.allCases) { tone in Text(tone.title).tag(tone) }
            }
            Button("Lyssna på valt ljud") { preferences.preview(selection.wrappedValue) }
                .buttonStyle(.borderless)
        }
    }
}

/// Uses the same mg/dL storage and expandable wheel presentation as the normal thresholds.
private struct GlucoseAlarmThresholdPicker: View {
    let title: String
    @Binding var value: Decimal
    let lower: Decimal
    let upper: Decimal
    let units: GlucoseUnits
    @State private var expanded = false

    private var selection: Binding<Decimal> {
        Binding(get: { min(upper, max(lower, value)) }, set: { value = min(upper, max(lower, $0)) })
    }

    private var values: [Decimal] {
        let setting = PickerSetting(value: selection.wrappedValue, step: 5, min: lower, max: upper, type: .glucose)
        let generated = PickerSettingsProvider.shared.generatePickerValues(from: setting, units: units)
        return Array(Set(generated + [lower, upper, selection.wrappedValue])).sorted()
    }

    private func display(_ value: Decimal) -> String {
        units == .mgdL ? value.description : value.formattedAsMmolL
    }

    var body: some View {
        VStack {
            Button { expanded.toggle() } label: {
                HStack {
                    Text(title).foregroundStyle(.primary)
                    Spacer()
                    Text(display(selection.wrappedValue)).foregroundStyle(expanded ? Color.accentColor : Color.primary)
                    Text(units.rawValue).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.borderless)
            if expanded {
                Picker(title, selection: selection) {
                    ForEach(values, id: \.self) { value in Text(display(value)).tag(value) }
                }
                .labelsHidden()
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: lower) { _, _ in value = selection.wrappedValue }
        .onChange(of: upper) { _, _ in value = selection.wrappedValue }
    }
}
