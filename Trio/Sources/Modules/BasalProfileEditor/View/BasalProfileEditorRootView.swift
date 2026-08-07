import Charts
import SwiftUI
import Swinject

extension BasalProfileEditor {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var editMode = EditMode.inactive

        let chartScale = Calendar.current
            .date(from: DateComponents(year: 2001, month: 01, day: 01, hour: 0, minute: 0, second: 0))
        let tzOffset = TimeZone.current.secondsFromGMT()

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var dateFormatter: DateFormatter {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.timeStyle = .short
            return formatter
        }

        private var rateFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal

            return formatter
        }

        var basalScheduleChart: some View {
            Chart {
                ForEach(state.chartData!, id: \.self) { profile in
                    let startDate = Calendar.current.startOfDay(for: Date())
                        .addingTimeInterval(profile.startDate.timeIntervalSinceReferenceDate + Double(tzOffset))
                    let endDate = Calendar.current.startOfDay(for: Date())
                        .addingTimeInterval(profile.endDate!.timeIntervalSinceReferenceDate + Double(tzOffset))
                    RectangleMark(
                        xStart: .value("start", startDate),
                        xEnd: .value("end", endDate),
                        yStart: .value("rate-start", profile.amount),
                        yEnd: .value("rate-end", 0)
                    ).foregroundStyle(
                        .linearGradient(
                            colors: [
                                Color.insulin.opacity(0.6),
                                Color.insulin.opacity(0.1)
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    ).alignsMarkStylesWithPlotArea()

                    LineMark(x: .value("End Date", endDate), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)

                    LineMark(x: .value("Start Date", startDate), y: .value("Amount", profile.amount))
                        .lineStyle(.init(lineWidth: 1)).foregroundStyle(Color.insulin)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.hour())
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 2)) { _ in
                    AxisValueLabel()
                    AxisGridLine(centered: true, stroke: StrokeStyle(lineWidth: 1, dash: [2, 4]))
                }
            }
            .chartXScale(
                domain: Calendar.current.startOfDay(for: Date()) ... Calendar.current.startOfDay(for: Date())
                    .addingTimeInterval(60 * 60 * 24)
            )
        }

        var saveButton: some View {
            ZStack {
                let shouldDisableButton = state.syncInProgress || state.items.isEmpty || !state.hasChanges

                Rectangle()
                    .frame(width: UIScreen.main.bounds.width, height: 65)
                    .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                    .background(.thinMaterial)
                    .opacity(0.8)
                    .clipShape(Rectangle())

                Group {
                    HStack {
                        Button(action: {
                            let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                            impactHeavy.impactOccurred()
                            state.save()
                        }, label: {
                            HStack {
                                if state.syncInProgress {
                                    ProgressView().padding(.trailing, 10)
                                }
                                Text(state.syncInProgress ? "Sparar..." : "Spara")
                            }
                            .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                            .padding(10)
                        })
                            .frame(width: UIScreen.main.bounds.width * 0.9, height: 40, alignment: .center)
                            .disabled(shouldDisableButton)
                            .background(shouldDisableButton ? Color(.systemGray4) : Color(.systemBlue))
                            .tint(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }.padding(5)
            }
        }

        var body: some View {
            Form {
                if !state.canAdd {
                    Section {
                        VStack(alignment: .leading) {
                            Text(
                                "Basalprofilen täcker 24 timmar. Du kan inte lägga till fler poster. Radera en befintlig post för att skapa utrymme för en ny post."
                            ).bold()
                        }
                    }.listRowBackground(Color.tabBar)
                }

                Section(header: Text("Schema")) {
                    if !state.items.isEmpty {
                        basalScheduleChart.padding(.vertical)
                    }

                    list
                }.listRowBackground(Color.chart)

                Section {
                    HStack {
                        Text("Total")
                            .bold()
                            .foregroundColor(.primary)
                        Spacer()
                        Text(rateFormatter.string(from: state.total as NSNumber) ?? "0")
                            .foregroundColor(.primary) +
                            Text(" E/dag")
                            .foregroundColor(.secondary)
                    }
                }.listRowBackground(Color.chart)

                Section {} footer: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: "note.text.badge.plus").foregroundStyle(.primary)
                            Text("Lägg till en post genom att klicka på 'Lägg till +' i det övre högra hörnet.")
                        }
                        HStack {
                            Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                            Text("Svep för att radera en post. Klicka på den för att redigera tid eller värde.")
                        }
                    }
                    .textCase(nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 30) { saveButton }
            .alert(isPresented: $state.showAlert) {
                Alert(
                    title: Text("Unable to Save"),
                    message: Text("Trio kunde inte kommunicera med din pump. Ändringar av baselen sparades inte."),
                    dismissButton: .default(Text("Stäng"))
                )
            }
            .onChange(of: state.items) {
                state.calcTotal()
                state.calculateChartData()
            }
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Basalprofil")
            .navigationBarTitleDisplayMode(.automatic)
            .toolbar(content: {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { state.add() }) {
                        HStack {
                            Text(" Lägg till")
                            Image(systemName: "plus")
                        }
                    }.disabled(!state.canAdd)
                }
            })
            .environment(\.editMode, $editMode)
            .onAppear {
                configureView()
                state.validate()
                state.calculateChartData()
            }
        }

        private func pickers(for index: Int) -> some View {
            Form {
                Section {
                    Picker(selection: $state.items[index].rateIndex, label: Text("Värde")) {
                        ForEach(0 ..< state.rateValues.count, id: \.self) { i in
                            Text(
                                (
                                    self.rateFormatter
                                        .string(from: state.rateValues[i] as NSNumber) ?? ""
                                ) + " E/h"
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].rateIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)

                Section {
                    Picker(selection: $state.items[index].timeIndex, label: Text("Tid")) {
                        ForEach(state.availableTimeIndices(index), id: \.self) { i in
                            Text(
                                self.dateFormatter
                                    .string(from: Date(
                                        timeIntervalSince1970: state
                                            .timeValues[i]
                                    ))
                            ).tag(i)
                        }
                    }
                    .onChange(of: state.items[index].timeIndex, { state.calcTotal() })
                }.listRowBackground(Color.chart)
            }
            .padding(.top)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle("Ange basalvärden")
            .navigationBarTitleDisplayMode(.automatic)
        }

        private var list: some View {
            List {
                ForEach(state.items.indexed(), id: \.1.id) { index, item in
                    NavigationLink(destination: pickers(for: index)) {
                        HStack {
                            Text("Rate").foregroundColor(.secondary)
                            Text(
                                "\(rateFormatter.string(from: state.rateValues[item.rateIndex] as NSNumber) ?? "0") U/hr"
                            )
                            Spacer()
                            Text("starts at").foregroundColor(.secondary)
                            Text(
                                "\(dateFormatter.string(from: Date(timeIntervalSince1970: state.timeValues[item.timeIndex])))"
                            )
                        }
                    }
                    .moveDisabled(true)
                }
                .onDelete(perform: onDelete)
            }
        }

        private func onDelete(offsets: IndexSet) {
            state.items.remove(atOffsets: offsets)
            state.validate()
            state.calculateChartData()
        }
    }
}
