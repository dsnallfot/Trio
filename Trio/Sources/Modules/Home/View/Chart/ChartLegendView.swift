import SwiftUI

struct ChartLegendView: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme

    var state: Home.StateModel

    @State var legendSheetDetent = PresentationDetent.large

    var body: some View {
        NavigationStack {
            /* VStack(alignment: .leading, spacing: 0) {
             Text(
                 "The main chart in Trio is made up of various elements and shapes. Find their meanings below."
             )
             .font(.subheadline)
             .foregroundColor(.secondary)
             .padding(.top, 50)
             .padding(.horizontal)
             */
            List {
                VStack(alignment: .leading) {
                    Text("Prognoser")
                        .bold()
                        .padding(.bottom, 5)
                        .textCase(.uppercase)

                    Text(
                        "Oref-algoritmen beräknar insulindoseringen utifrån ett antal olika scenarier som uppskattas med hjälp av olika typer av prognoser."
                    )
                    .font(.subheadline)
                    .foregroundColor(.primary)

                    if state.forecastDisplayType == .lines {
                        legendLinesView
                    } else {
                        legendConeOfUncertaintyView
                    }
                }
                .listRowBackground(Color.gray.opacity(0.1))

                VStack(alignment: .leading) {
                    Text("Övriga element och symboler")
                        .bold()
                        .padding(.bottom, 5)
                        .textCase(.uppercase)

                    DefinitionRow(
                        term: "Schemalagd basal",
                        definition: VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Den prickade linjen visar din schemalagda basal timme för timme."
                            )

                            Text(
                                "Du kan visa eller ändra dina schemalagda basal under Inställningar > Behandling > Basalprofil."
                            )
                        },
                        color: Color.insulin,
                        iconString: "ellipsis"
                    )

                    DefinitionRow(
                        term: "Tillfällig basal (TBR)",
                        definition: Text(
                            "Visar aktuella eller tidigare tillfälliga basaler som antingen satts av oref-algoritmen eller manuellt."
                        ),
                        color: Color.insulin,
                        iconString: "square"
                    )

                    DefinitionRow(
                        term: "Pump pausad",
                        definition: Text(
                            "Visar när insulintillförseln varit pausad, det vill säga när pumpen varit stoppad."
                        ),
                        color: Color.loopGray.opacity(
                            colorScheme == .dark ? 0.3 : 0.8
                        ),
                        iconString: "square.fill"
                    )

                    DefinitionRow(
                        term: "CGM-värde",
                        definition: VStack(alignment: .leading, spacing: 10) {
                            if state.settingsManager.settings.smoothGlucose {
                                Text(
                                    "Visar glukosvärden från din CGM som jämnats ut med Savitzky–Golay-filtret. De visade värdena kan därför skilja sig något från de faktiska CGM-värdena."
                                )

                                Text(
                                    "Beroende på dina gränssnittsinställningar visas värdena antingen med statiska färger (röd, grön och orange) eller med ett dynamiskt färgspektrum."
                                )
                            } else {
                                Text(
                                    "Visar glukosvärden från din CGM. Beroende på dina gränssnittsinställningar visas värdena antingen med statiska färger (röd, grön och orange) eller med ett dynamiskt färgspektrum."
                                )
                            }

                            Text(
                                "Du kan ändra hur glukosvärden visas under Inställningar > Funktioner > Användargränssnitt > Glukosfärgschema."
                            )

                            if state.settingsManager.settings.smoothGlucose {
                                Text(
                                    "Du kan stänga av utjämning under Inställningar > Enheter > Kontinuerlig glukosmätare > Utjämna glukosvärde."
                                )
                            }
                        },
                        color: Color.green,
                        iconString: state.settingsManager.settings.smoothGlucose
                            ? "record.circle.fill"
                            : "circle.fill"
                    )

                    DefinitionRow(
                        term: "Manuellt glukosvärde",
                        definition: Text(
                            "Ett manuellt registrerat blodsockervärde, till exempel från ett fingerstick."
                        ),
                        color: Color.red,
                        iconString: "drop.fill"
                    )

                    DefinitionRow(
                        term: "Bolus",
                        definition: Text(
                            "Visar en insulindos. Det kan vara en automatisk mikrodos (SMB), en manuellt given bolus eller insulin som registrerats från en extern källa, exempelvis en insulinpenna."
                        ),
                        color: Color.insulin,
                        iconString: "arrowtriangle.down.fill"
                    )

                    DefinitionRow(
                        term: "Kolhydratregistrering",
                        definition: Text(
                            "Visar registrerade kolhydrater som används för att beräkna insulinbehandlingen."
                        ),
                        color: Color.orange,
                        iconString: "arrowtriangle.down.fill",
                        shouldRotateIcon: true
                    )

                    DefinitionRow(
                        term: "Kolhydratekvivalent för fett och protein",
                        definition: VStack(alignment: .leading, spacing: 10) {
                            Text(
                                "Visar den kolhydratekvivalent som beräknats från fett och protein enligt Warszawametoden."
                            )

                            Text(
                                "Du kan aktivera eller konfigurera Warszawametoden under Inställningar > Funktioner > Måltidsinställningar."
                            )
                        },
                        color: Color.brown,
                        iconString: "circle.fill"
                    )

                    DefinitionRow(
                        term: "Override",
                        definition: Text(
                            "Visar när en override varit aktiv. En override kan tillfälligt ändra basal, insulinkänslighet, kolhydratkvot, glukosmål eller om Trio får ge SMB."
                        ),
                        color: Color.purple.opacity(0.4),
                        iconString: "button.horizontal.fill"
                    )

                    DefinitionRow(
                        term: "Tillfälligt mål",
                        definition: Text(
                            "Visar när ett tillfälligt glukosmål varit aktivt, vilket kan påverka när och hur mycket insulin som ges."
                        ),
                        color: Color.green.opacity(0.4),
                        iconString: "button.horizontal.fill"
                    )

                    DefinitionRow(
                        term: "Tidigare IOB (aktivt insulin)",
                        definition: Text(
                            "Visar det IOB-värde som algoritmen beräknade vid en viss tidpunkt. Dessa värden är historiska ögonblicksbilder och ändras inte i efterhand."
                        ),
                        color: Color.insulin.opacity(0.8),
                        iconString: "line.diagonal"
                    )

                    DefinitionRow(
                        term: "Tidigare COB (aktiva kolhydrater)",
                        definition: Text(
                            "Visar det COB-värde som algoritmen beräknade vid en viss tidpunkt. Dessa värden är historiska ögonblicksbilder och ändras inte i efterhand."
                        ),
                        color: Color.orange.opacity(0.8),
                        iconString: "line.diagonal"
                    )
                }
                .listRowBackground(Color.gray.opacity(0.1))
            }
            .padding(.top, 30)
            .scrollContentBackground(.hidden)
            // .padding(.trailing, 10)

            // Ger tillräckligt med extra skrollutrymme så den sista
            // listposten kan skrollas upp ovanför den flytande knappen.
            .contentMargins(.bottom, 110, for: .scrollContent)
            // }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                let bottomExtension: CGFloat = 34

                ZStack(alignment: .bottom) {
                    LinearGradient(
                        colors: [
                            .clear,
                            Color(.systemBackground).opacity(0.5),
                            Color(.systemBackground).opacity(0.8)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .allowsHitTesting(false)

                    Group {
                        if #available(iOS 26.0, *) {
                            Button {
                                state.isLegendPresented.toggle()
                            } label: {
                                Text("Uppfattat!")
                                    .bold()
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 40,
                                        alignment: .center
                                    )
                            }
                            .buttonStyle(.glassProminent)
                        } else {
                            Button {
                                state.isLegendPresented.toggle()
                            } label: {
                                Text("Uppfattat!")
                                    .bold()
                                    .frame(
                                        maxWidth: .infinity,
                                        minHeight: 40,
                                        alignment: .center
                                    )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, bottomExtension + 8)
                }
                .frame(maxWidth: .infinity)
                .offset(y: bottomExtension)
                .ignoresSafeArea(edges: .bottom)
            }
            .navigationBarTitle("Förklaring av diagrammet", displayMode: .inline)
            .listSectionSpacing(10)
            .ignoresSafeArea(edges: .top)
            .presentationDetents(
                [.fraction(0.9), .large],
                selection: $legendSheetDetent
            )
        }
    }

    var legendLinesView: some View {
        Group {
            DefinitionRow(
                term: "IOB (aktivt insulin)",
                definition: Text(
                    "Prognos över framtida glukosvärden baserat på mängden aktivt insulin i kroppen."
                ),
                color: .insulin
            )

            DefinitionRow(
                term: "ZT (nolltemp)",
                definition: Text(
                    "Visar det sämsta prognostiserade scenariot om inga kolhydrater absorberas och insulintillförseln stoppas tills glukoset börjar stiga."
                ),
                color: .zt
            )

            DefinitionRow(
                term: "COB (aktiva kolhydrater)",
                definition: Text(
                    "Prognos över framtida glukosvärden baserat på hur många kolhydrater som fortfarande absorberas."
                ),
                color: .loopYellow
            )

            DefinitionRow(
                term: "UAM (oregistrerad måltid)",
                definition: Text(
                    "Prognos över framtida glukosnivåer och insulinbehov vid oregistrerade måltider eller andra oväntade glukosstegringar."
                ),
                color: .uam
            )
        }
    }

    var legendConeOfUncertaintyView: some View {
        DefinitionRow(
            term: "Osäkerhetskon",
            definition: VStack(alignment: .leading, spacing: 10) {
                Text(
                    "För att göra diagrammet enklare visas oref-algoritmens olika prognoskurvor som en osäkerhetskon. Den visar det möjliga spannet för framtida glukosutveckling baserat på aktuell data och algoritmens beräkningar."
                )

                Text(
                    "Du kan ändra hur prognosen visas under Inställningar > Funktioner > Användargränssnitt > Typ av prognosvisning."
                )
            },
            color: Color.cyan.opacity(0.4)
        )
    }
}
