import SwiftUI

struct LoopStatusHelpView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    var state: Home.StateModel
    var helpSheetDetent: Binding<PresentationDetent>
    var isHelpSheetPresented: Binding<Bool>

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading) {
                Text(
                    "Oref-algoritmen ger doseringsrekommendationer och visar viktiga variabler, beslut om tillfälliga basaldoser eller supermikrobolusar (SMB), samt ett \"reason\"-fält som förklarar varför algoritmen agerar som den gör. Nedan hittar du en beskrivning av de viktigaste begreppen i detta \"reason\"-fält:"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 60)

                List {
                    DefinitionRow(
                        term: "Autosens ratio",
                        definition: Text(
                            "Förhållandet som beskriver hur insulinkänslig eller insulinresistent du är i den aktuella loopcykeln. Grundvärde = 1.0, känsligare < 1.0, mer insulinresistent > 1.0."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "ISF",
                        definition: Text(
                            "Det första värdet är din insulinkänslighetsfaktor (ISF) enligt din profil. Det andra värdet, efter pilen, är den justerade ISF som användes vid den senaste automatiska dosberäkningen."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "COB",
                        definition: Text(
                            "Mängden aktiva kolhydrater (COB) som användes vid den senaste automatiska dosberäkningen."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Dev",
                        definition: Text(
                            "Förkortning för \"Deviation\". Visar hur mycket den faktiska glukosförändringen avvek från den beräknade BGI."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "BGI",
                        definition: Text(
                            "Visar hur mycket ditt glukos förväntas stiga eller sjunka enbart baserat på insulinets effekt."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "CR",
                        definition: Text(
                            "Det första värdet är ditt kolhydratförhållande (CR) enligt din profil. Det andra värdet, efter pilen, är det justerade CR som användes vid den senaste automatiska dosberäkningen."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Mål",
                        definition: Text(
                            "Det första värdet är ditt målblodsocker enligt dina inställningar. Det andra värdet, efter pilen, är det justerade målblodsockret som användes vid den senaste automatiska dosberäkningen. Ett andra värde visas om du använder ett tillfälligt mål, en override eller någon av inställningarna för Target Behavior."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "minPredBG",
                        definition: Text(
                            "Det lägsta framtida glukosvärde som Trio har prognostiserat."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "minGuardBG",
                        definition: Text(
                            "Det lägsta prognostiserade glukosvärdet under den återstående insulinverkningstiden (DIA)."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "IOBpredBG",
                        definition: Text(
                            "Det prognostiserade glukosvärdet om 4 timmar, beräknat enbart utifrån aktivt insulin (IOB)."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "COBpredBG",
                        definition: Text(
                            "Det prognostiserade glukosvärdet om 4 timmar, beräknat utifrån aktuellt IOB och COB."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "UAMpredBG",
                        definition: Text(
                            "Det prognostiserade glukosvärdet om 4 timmar, baserat på de aktuella avvikelserna som gradvis avtar till noll i samma takt som de har gjort den senaste tiden."
                        ),
                        color: .green
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "TDD",
                        definition: Text(
                            "Förkortning för \"Total Daily Dose\". Den totala mängden insulin som administrerats under de senaste 24 timmarna, både basal och bolus."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Bolus/Basal %",
                        definition: Text(
                            "Visar hur stor andel av det insulin som levererats under de senaste 24 timmarna som gavs som basalinsulin respektive bolus."
                        ),
                        color: .insulin
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Dynamisk ISF/CR",
                        definition: Text(
                            "\"På/På\" betyder att både Dynamisk ISF och Dynamisk CR är aktiverade. \"På/Av\" betyder att endast Dynamisk ISF är aktiverad. Dynamisk CR kan inte aktiveras om Dynamisk ISF är avstängd."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Sigmoid funktion",
                        definition: Text(
                            "Om detta visas betyder det att Sigmoid Dynamisk ISF är aktiverad."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Logaritmisk formel",
                        definition: Text(
                            "Om detta visas betyder det att Logaritmisk Dynamisk ISF är aktiverad."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "AF",
                        definition: Text(
                            "Visar den justeringsfaktor (AF) som används för antingen Logarithmisk eller Sigmoid Dynamisk ISF."
                        ),
                        color: .zt
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "SMB Ratio",
                        definition: Text(
                            "Den SMB-andel av den beräknade insulinmängden som levereras som en supermikrobolus."
                        ),
                        color: .uam
                    ).listRowBackground(Color.gray.opacity(0.1))

                    DefinitionRow(
                        term: "Smoothing",
                        definition: Text(
                            "Visar att glukosutjämning (glucose smoothing) är aktiverad."
                        ),
                        color: .gray
                    ).listRowBackground(Color.gray.opacity(0.1))
                }
                .scrollContentBackground(.hidden)
                .navigationBarTitle("Ordlista", displayMode: .inline)
                .padding(.bottom, 15)

                Button {
                    isHelpSheetPresented.wrappedValue.toggle()
                } label: {
                    Text("Got it!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
                }
                .buttonStyle(.bordered)
                .padding(.top)
            }
            .padding([.horizontal, .bottom])
            .listSectionSpacing(10)
            .ignoresSafeArea(edges: .top)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: helpSheetDetent
            )
        }
    }

    var legendLinesView: some View {
        Group {
            DefinitionRow(
                term: "IOB (Insulin on Board)",
                definition: Text(
                    "Forecasts future glucose readings based on the amount of insulin still active in the body."
                ),
                color: .insulin
            )

            DefinitionRow(
                term: "ZT (Zero-Temp)",
                definition: Text(
                    "Forecasts the worst-case future glucose reading scenario if no carbs are absorbed and insulin delivery is stopped until glucose starts rising."
                ),
                color: .zt
            )

            DefinitionRow(
                term: "COB (Carbs on Board)",
                definition: Text(
                    "Forecasts future glucose reading changes by considering the amount of carbohydrates still being absorbed in the body."
                ),
                color: .loopYellow
            )

            DefinitionRow(
                term: "UAM (Unannounced Meal)",
                definition: Text(
                    "Forecasts future glucose levels and insulin dosing needs for unexpected meals or other causes of glucose reading increases without prior notice."
                ),
                color: .uam
            )
        }
    }

    var legendConeOfUncertaintyView: some View {
        DefinitionRow(
            term: "Cone of Uncertainty",
            definition: VStack(alignment: .leading, spacing: 10) {
                Text(
                    "For simplicity reasons, oref's various forecast curves are displayed as a \"Cone of Uncertainty\" that depicts a possible, forecasted range of future glucose fluctuation based on the current data and the algothim's result."
                )
                Text(
                    "To modify how the forecast is displayed, go to Settings > Features > User Interface > Forecast Display Type."
                )
            },
            color: Color.blue.opacity(0.5)
        )
    }
}
