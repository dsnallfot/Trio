import SwiftUI
import Swinject

struct AlarmKitSettings: BaseView {
    let resolver: Resolver
    @StateObject var state = GlucoseNotificationSettings.StateModel()

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            GlucoseAlarmSettingsSection(low: $state.lowGlucose, high: $state.highGlucose, units: state.units)
            SystemAlarmSettingsSection()
        }
        .listSectionSpacing(sectionSpacing)
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .onAppear {
            configureView()
            state.refreshGlucoseThresholds()
        }
        .navigationBarTitle("Trio-alarm")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
