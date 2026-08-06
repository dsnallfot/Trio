import SwiftUI
import Swinject

extension CalendarEventSettings {
    struct RootView: BaseView {
        let resolver: Resolver
        @StateObject var state = StateModel()
        @State private var shouldDisplayHint: Bool = false
        @State var hintDetent = PresentationDetent.large
        @State var selectedVerboseHint: AnyView?
        @State var hintLabel: String?
        @State private var decimalPlaceholder: Decimal = 0.0
        @State private var booleanPlaceholder: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @EnvironmentObject var appIcons: Icons
        @Environment(AppState.self) var appState

        var body: some View {
            List {
                SettingInputSection(
                    decimalValue: $decimalPlaceholder,
                    booleanValue: $state.useCalendar,
                    shouldDisplayHint: $shouldDisplayHint,
                    selectedVerboseHint: Binding(
                        get: { selectedVerboseHint },
                        set: {
                            selectedVerboseHint = $0.map { AnyView($0) }
                            hintLabel = "Skapa händelser i Kalender"
                        }
                    ),
                    units: state.units,
                    type: .boolean,
                    label: "Skapa händelser i Kalender",
                    miniHint: "Visa aktuella diabetesdata med hjälp av kalenderhändelser.",
                    verboseHint:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard: AV").bold()

                        Text(
                            "När funktionen är aktiverad skapar Trio en anpassningsbar kalenderhändelse med ditt aktuella glukosvärde efter varje slutförd loopcykel."
                        )

                        Text(
                            "Detta är användbart om du använder CarPlay eller andra externa tjänster som begränsar visningen av de flesta appar men tillåter information från Kalender."
                        )

                        Text(
                            "När funktionen är aktiverad visas de tillgängliga anpassningsalternativen. Du kan välja vilken kalender som ska användas, visa emoji-etiketter och inkludera IOB- och COB-värden."
                        )

                        Text(
                            "Obs: När en ny kalenderhändelse skapas tas den föregående händelsen bort."
                        )
                    },
                    headerText: "Diabetesdata som kalenderhändelse"
                )

                if state.calendarIDs.isNotEmpty, state.useCalendar {
                    Section {
                        VStack {
                            Picker(
                                "Välj kalender",
                                selection: $state.currentCalendarID
                            ) {
                                ForEach(state.calendarIDs, id: \.self) {
                                    Text($0).tag($0)
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.chart)

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.displayCalendarEmojis,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Visa emojier som etiketter"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Visa emojier som etiketter",
                        miniHint: "Använd emojier i kalenderhändelser. Se hjälptexten för mer information.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()

                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "När funktionen är aktiverad visar den skapade kalenderhändelsen om glukosvärdet ligger inom eller utanför målområdet med hjälp av följande färgade emojier:"
                                )

                                Text("🟢: Inom målområdet")
                                Text("🟠: Över målområdet")
                                Text("🔴: Under målområdet")
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                Text(
                                    "Om \"Visa IOB och COB\" också är aktiverat ersätts \"IOB\" och \"COB\" med följande emojier:"
                                )

                                Text("💉: IOB")
                                Text("🥨: COB")
                            }
                        }
                    )

                    SettingInputSection(
                        decimalValue: $decimalPlaceholder,
                        booleanValue: $state.displayCalendarIOBandCOB,
                        shouldDisplayHint: $shouldDisplayHint,
                        selectedVerboseHint: Binding(
                            get: { selectedVerboseHint },
                            set: {
                                selectedVerboseHint = $0.map { AnyView($0) }
                                hintLabel = "Visa IOB och COB"
                            }
                        ),
                        units: state.units,
                        type: .boolean,
                        label: "Visa IOB och COB",
                        miniHint: "Inkludera IOB och COB i kalenderhändelsens information.",
                        verboseHint: VStack(alignment: .leading, spacing: 10) {
                            Text("Standard: AV").bold()

                            Text(
                                "När funktionen är aktiverad inkluderar Trio aktuella IOB- och COB-värden tillsammans med det aktuella glukosvärdet i varje kalenderhändelse som skapas."
                            )
                        }
                    )
                } else if state.useCalendar {
                    if #available(iOS 17.0, *) {
                        Text(
                            "Om inga kalendrar visas här går du till Inställningar → Trio → Kalendrar och ändrar behörigheten till \"Full åtkomst\"."
                        )
                        .font(.footnote)

                        Button("Öppna Inställningar") {
                            // Hämta webbadressen till inställningarna och öppna den
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
            }
            .listSectionSpacing(sectionSpacing)
            .sheet(isPresented: $shouldDisplayHint) {
                SettingInputHintView(
                    hintDetent: $hintDetent,
                    shouldDisplayHint: $shouldDisplayHint,
                    hintLabel: hintLabel ?? "",
                    hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                    sheetTitle: "Hjälp"
                )
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onAppear(perform: configureView)
            .navigationTitle("Kalenderhändelser")
            .navigationBarTitleDisplayMode(.automatic)
        }
    }
}
