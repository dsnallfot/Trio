import SwiftUI
import Swinject

struct NightscoutImportResultView: BaseView {
    var resolver: any Swinject.Resolver

    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: String?
    @State private var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @State private var hasVisitedBasalProfileEditor = false
    @State private var hasVisitedISFEditor = false
    @State private var hasVisitedCREditor = false
    @State private var hasVisitedPumpSettingsEditor = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    private var allViewsVisited: Bool {
        hasVisitedBasalProfileEditor &&
            hasVisitedISFEditor &&
            hasVisitedCREditor &&
            hasVisitedPumpSettingsEditor
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Import av Nightscoutdata"),
                    content: {
                        Text(
                            "Trio har importerat din Nightscoutprofil och sparat den som dina behandlingsinställningar. "
                        ) +
                            Text("Detta ersätter dina tidigare behandlingsinställningar.").bold().foregroundColor(.accentColor)
                        Text("Vänligen granska följande inställningar:").bold()
                    }
                ).listRowBackground(Color.chart)

                Section {
                    NavigationLink(
                        destination: BasalProfileEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedBasalProfileEditor = true }
                    ) {
                        HStack {
                            Text("Basalprofil")
                            if hasVisitedBasalProfileEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedBasalProfileEditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: ISFEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedISFEditor = true }
                    ) {
                        HStack {
                            Text("Insulin Sensitivities")
                            if hasVisitedISFEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedISFEditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: CarbRatioEditor.RootView(resolver: resolver)
                            .onDisappear { hasVisitedCREditor = true }
                    ) {
                        HStack {
                            Text("Insulinkvoter")
                            if hasVisitedCREditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedCREditor ? .secondary : .primary)
                    }

                    NavigationLink(
                        destination: ReviewInsulinActionView(resolver: resolver, state: state)
                            .onDisappear { hasVisitedPumpSettingsEditor = true }
                    ) {
                        HStack {
                            Text("Insulinets verkningstid")
                            if hasVisitedPumpSettingsEditor {
                                Image(systemName: "checkmark.circle.fill")
                                    .imageScale(.large)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Color.green)
                            }
                        }.foregroundColor(hasVisitedPumpSettingsEditor ? .secondary : .primary)
                    }
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Button {
                            state.isImportResultReviewPresented = false
                        } label: {
                            Text("Slutför").font(.title3)
                        }
                        .disabled(!allViewsVisited)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .tint(.white)
                    }
                }.listRowBackground(allViewsVisited ? Color(.systemBlue) : Color(.systemGray4))
            }
            .navigationTitle("Granska import")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .interactiveDismissDisabled(true)
            .screenNavigation(self)
        }
    }
}
