import CoreData
import SpriteKit
import SwiftDate
import SwiftUI
import Swinject

struct TimePicker: Identifiable {
    var active: Bool
    let hours: Int16
    var id: String { hours.description }
}

extension Home {
    struct RootView: BaseView {
        let resolver: Resolver
        let safeAreaSize: CGFloat = 0.08

        @Environment(\.managedObjectContext) var moc
        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        @State var state = StateModel()

        @State var settingsPath = NavigationPath()
        @State var isStatusPopupPresented = false
        @State var showCancelAlert = false
        @State var showCancelConfirmDialog = false
        @State var isConfirmStopOverrideShown = false
        @State var isConfirmStopOverridePresented = false
        @State var isConfirmStopTempTargetShown = false
        @State var isMenuPresented = false
        @State var showTreatments = false
        @State var selectedTab: Int = 0
        static let treatmentTabTag = 4
        @State var showPumpSelection: Bool = false
        @State var notificationsDisabled = false
        @State var timeButtons: [TimePicker] = [
            TimePicker(active: false, hours: 3),
            TimePicker(active: false, hours: 6),
            TimePicker(active: false, hours: 12),
            TimePicker(active: false, hours: 24)
        ]

        @FetchRequest(fetchRequest: OverrideStored.fetch(
            NSPredicate.lastActiveOverride,
            ascending: false,
            fetchLimit: 1
        )) var latestOverride: FetchedResults<OverrideStored>

        @FetchRequest(fetchRequest: TempTargetStored.fetch(
            NSPredicate.lastActiveTempTarget,
            ascending: false,
            fetchLimit: 1
        )) var latestTempTarget: FetchedResults<TempTargetStored>

        var adjustmentTint: Color? {
            if overrideString != nil { return Color.purple }
            if tempTargetString != nil { return Color.loopGreen }
            return nil
        }

        var bolusProgressFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimum = 0
            formatter.maximumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.minimumFractionDigits = state.settingsManager.preferences.bolusIncrement > 0.05 ? 1 : 2
            formatter.allowsFloats = true
            formatter.roundingIncrement = Double(state.settingsManager.preferences.bolusIncrement) as NSNumber
            return formatter
        }

        private var fetchedTargetFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var historySFSymbol: String {
            if #available(iOS 17.0, *) {
                return "book.pages"
            } else {
                return "book"
            }
        }

        var glucoseView: some View {
            CurrentGlucoseView(
                timerDate: state.timerDate,
                units: state.units,
                alarm: state.alarm,
                lowGlucose: state.lowGlucose,
                highGlucose: state.highGlucose,
                cgmAvailable: state.cgmAvailable,
                currentGlucoseTarget: state.currentGlucoseTarget,
                glucoseColorScheme: state.glucoseColorScheme,
                glucose: state.latestTwoGlucoseValues
            ).scaleEffect(0.9)
                .onTapGesture {
                    state.openCGM()
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.showModal(for: .snooze)
                }
        }

        var pumpView: some View {
            PumpView(
                reservoir: state.reservoir,
                name: state.pumpName,
                expiresAtDate: state.pumpExpiresAtDate,
                timerDate: state.timerDate,
                timeZone: state.timeZone,
                pumpStatusHighlightMessage: state.pumpStatusHighlightMessage,
                battery: state.batteryFromPersistence
            )
            .onTapGesture {
                if state.pumpDisplayState == nil {
                    // shows user confirmation dialog with pump model choices, then proceeds to setup
                    showPumpSelection.toggle()
                } else {
                    // sends user to pump settings
                    state.setupPump.toggle() // Daniel: Maybe disable or add auth to avoid accidentally tapping
                }
            }
        }

        var tempBasalString: String? {
            guard let lastTempBasal = state.tempBasals.last?.tempBasal, let tempRate = lastTempBasal.rate else {
                return nil
            }
            let rateString = Formatter.decimalFormatterWithTwoFractionDigits.string(from: tempRate as NSNumber) ?? "0"
            var manualBasalString = ""

            if let apsManager = state.apsManager, apsManager.isManualTempBasal {
                manualBasalString = NSLocalizedString(
                    " - Manual Basal ⚠️",
                    comment: "Manual Temp basal"
                )
            }

            return rateString + " " + NSLocalizedString(" E/h", comment: "Unit per hour with space") + manualBasalString
        }

        var overrideString: String? {
            guard let latestOverride = latestOverride.first else {
                return nil
            }

            let percent = latestOverride.percentage
            let percentString = percent == 100 ? "" : "\(percent.formatted(.number)) %"

            let unit = state.units
            var target = (latestOverride.target ?? 100) as Decimal
            target = unit == .mmolL ? target.asMmolL : target

            var targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " + unit
                .rawValue
            if tempTargetString != nil {
                targetString = ""
            }

            let duration = latestOverride.duration ?? 0
            let addedMinutes = Int(truncating: duration)
            let date = latestOverride.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            let indefinite = latestOverride.indefinite
            var durationString = ""

            if !indefinite {
                if newDuration >= 1 {
                    durationString = formatHrMin(Int(newDuration))
                } else if newDuration > 0 {
                    durationString = "\(Int(newDuration * 60)) s"

                } else {
                    /// Do not show the Override anymore
                    Task {
                        guard let objectID = self.latestOverride.first?.objectID else { return }
                        await state.cancelOverride(withID: objectID)
                    }
                }
            }

            let smbScheduleString = latestOverride
                .smbIsScheduledOff && ((latestOverride.start?.stringValue ?? "") != (latestOverride.end?.stringValue ?? ""))
                ? " \(formatTimeRange(start: latestOverride.start?.stringValue, end: latestOverride.end?.stringValue))"
                : ""

            let smbToggleString = latestOverride.smbIsOff || latestOverride
                .smbIsScheduledOff ? "SMB av\(smbScheduleString)" : ""

            let components = [durationString, percentString, targetString, smbToggleString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: " • ")
        }

        var tempTargetString: String? {
            guard let latestTempTarget = latestTempTarget.first else {
                return nil
            }
            let duration = latestTempTarget.duration
            let addedMinutes = Int(truncating: duration ?? 0)
            let date = latestTempTarget.date ?? Date()
            let newDuration = max(
                Decimal(Date().distance(to: date.addingTimeInterval(addedMinutes.minutes.timeInterval)).minutes),
                0
            )
            var durationString = ""
            var percentageString = ""
            var target = (latestTempTarget.target ?? 100) as Decimal
            var halfBasalTarget: Decimal = 160
            if latestTempTarget.halfBasalTarget != nil {
                halfBasalTarget = latestTempTarget.halfBasalTarget! as Decimal
            } else { halfBasalTarget = state.settingHalfBasalTarget }
            var showPercentage = false
            if target > 100, state.isExerciseModeActive || state.highTTraisesSens { showPercentage = true }
            if target < 100, state.lowTTlowersSens { showPercentage = true }
            if showPercentage {
                percentageString =
                    " \(state.computeAdjustedPercentage(halfBasalTargetValue: halfBasalTarget, tempTargetValue: target))%" }
            target = state.units == .mmolL ? target.asMmolL : target
            let targetString = target == 0 ? "" : (fetchedTargetFormatter.string(from: target as NSNumber) ?? "") + " " +
                state.units.rawValue + percentageString

            if newDuration >= 1 {
                durationString =
                    "\(newDuration.formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) min"
            } else if newDuration > 0 {
                durationString =
                    "\((newDuration * 60).formatted(.number.grouping(.never).rounded().precision(.fractionLength(0)))) s"
            } else {
                /// Do not show the Temp Target anymore
                Task {
                    guard let objectID = self.latestTempTarget.first?.objectID else { return }
                    await state.cancelTempTarget(withID: objectID)
                }
            }

            let components = [targetString, durationString].filter { !$0.isEmpty }
            return components.isEmpty ? nil : components.joined(separator: ", ")
        }

        var timeIntervalButtons: some View {
            // let buttonColor = (colorScheme == .dark ? Color.white : Color.black).opacity(0.8)
            let buttonColor = Color.secondary

            return HStack(alignment: .center) {
                ForEach(timeButtons) { button in
                    Button(action: {
                        state.hours = button.hours
                    }) {
                        Group {
                            if button.active {
                                Text(
                                    NSLocalizedString(button.hours.description, comment: "") + " " +
                                        NSLocalizedString("h", comment: "h")
                                )
                            } else {
                                Text(NSLocalizedString(button.hours.description, comment: ""))
                            }
                        }
                        .font(.footnote)
                        .fontWeight(button.active ? .semibold : .regular)
                        .padding(.vertical, 5)
                        .padding(.horizontal, 10)
                        .foregroundColor(
                            button
                                .active ? (colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white) : buttonColor
                        )
                        .background(button.active ? buttonColor.opacity(colorScheme == .dark ? 1 : 0.8) : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(button.active ? buttonColor.opacity(0.4) : Color.clear, lineWidth: 1)
                        )
                    }
                }
            }
        }

        var statsIconString: String {
            if #available(iOS 18, *) {
                return "chart.line.text.clipboard"
            } else {
                return "list.clipboard"
            }
        }

        @ViewBuilder private func tappableButton(
            buttonColor: Color,
            // label: String,
            iconString: String,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: {
                action()
            }) {
                HStack {
                    Image(systemName: iconString)
                    // Text(label)
                }
                // .font(.footnote)
                .font(.title2)
                .padding(.vertical, 5)
                .padding(.horizontal, 10)
                .foregroundStyle(buttonColor)
                /* .overlay(
                     Capsule()
                         .stroke(buttonColor.opacity(0.4), lineWidth: 1)
                 ) */
            }
        }

        @ViewBuilder func mainChart(geo: GeometryProxy) -> some View {
            ZStack {
                MainChartView(
                    geo: geo,
                    safeAreaSize: notificationsDisabled == true ? safeAreaSize : 0,
                    units: state.units,
                    hours: state.filteredHours,
                    highGlucose: state.highGlucose,
                    lowGlucose: state.lowGlucose,
                    currentGlucoseTarget: state.currentGlucoseTarget,
                    glucoseColorScheme: state.glucoseColorScheme,
                    screenHours: state.hours,
                    displayXgridLines: state.displayXgridLines,
                    displayYgridLines: state.displayYgridLines,
                    thresholdLines: state.thresholdLines,
                    state: state
                )
            }
            .padding(.bottom, UIDevice.adjustPadding(min: 0, max: nil))
        }

        func highlightButtons() {
            for i in 0 ..< timeButtons.count {
                timeButtons[i].active = timeButtons[i].hours == state.hours
            }
        }

        @ViewBuilder func rightHeaderPanel(_: GeometryProxy) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                /// Loop view at bottomLeading
                LoopView(
                    closedLoop: state.closedLoop,
                    timerDate: state.timerDate,
                    isLooping: state.isLooping,
                    lastLoopDate: state.lastLoopDate,
                    manualTempBasal: state.manualTempBasal,
                    determination: state.determinationsFromPersistence
                )
                .onTapGesture {
                    state.isLoopStatusPresented = true
                }
                .onLongPressGesture {
                    let impactHeavy = UIImpactFeedbackGenerator(style: .heavy)
                    impactHeavy.impactOccurred()
                    state.runLoop()
                }
                /// eventualBG string at bottomTrailing

                if let eventualBG = state.enactedAndNonEnactedDeterminations.first?.eventualBG {
                    let bg = eventualBG as Decimal
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
                        Text(
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: (
                                    state.units == .mmolL ? bg
                                        .asMmolL : bg
                                ) as NSNumber
                            )!
                        ).font(.subheadline).fontWeight(.semibold).fontDesign(.rounded).foregroundColor(.primary)
                    }
                    // aligns the evBG icon exactly with the first pixel of loop status icon
                    .padding(.leading, 10)
                    .onTapGesture {
                        state.isLoopStatusPresented = true
                    }
                } else {
                    HStack {
                        Image(systemName: "arrow.right.circle")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(.secondary)
                        Text("--")
                            .font(.subheadline).fontWeight(.semibold).fontDesign(.rounded).foregroundColor(.secondary)
                    }
                    .padding(.leading, 10)
                    .onTapGesture {
                        state.isLoopStatusPresented = true
                    }
                }
            }
        }

        @ViewBuilder func mealPanel(_: GeometryProxy) -> some View {
            HStack {
                HStack {
                    // Image(systemName: "syringe.fill")
                    Text("IOB")
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(Color.insulin)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits
                                .string(from: (state.enactedAndNonEnactedDeterminations.first?.iob ?? 0) as NSNumber) ?? "0"
                        ) +
                            NSLocalizedString(" E", comment: "Insulin unit")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }

                Spacer()

                HStack {
                    // Image(systemName: "fork.knife")
                    Text("COB")
                        .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        .foregroundColor(.loopYellow)
                    Text(
                        (
                            Formatter.decimalFormatterWithTwoFractionDigits.string(
                                from: NSNumber(value: state.enactedAndNonEnactedDeterminations.first?.cob ?? 0)
                            ) ?? "0"
                        ) +
                            NSLocalizedString(" g", comment: "gram of carbs")
                    )
                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                }

                Spacer()

                if state.maxIOB == 0.0 {
                    HStack {
                        Image(systemName: "exclamationmark.circle.fill")
                        Text("MaxIOB: 0 U")
                    }.bold()
                        .foregroundStyle(Color.red)
                        .font(.callout)
                } else {
                    HStack {
                        if state.pumpSuspended {
                            Text("Pump suspended")
                                .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                                .foregroundColor(.loopGray)
                        } else if let tempBasalString = tempBasalString {
                            Image(systemName: "drop.circle")
                                .font(.callout)
                                .foregroundColor(Color.insulin.opacity(0.8))
                            if tempBasalString.count > 5 {
                                Text(tempBasalString)
                                    .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                    .truncationMode(.tail)
                                    .allowsTightening(true)
                            } else {
                                // Short strings can just display normally
                                Text(tempBasalString).font(.callout).fontWeight(.bold).fontDesign(.rounded)
                            }
                        } else {
                            Image(systemName: "drop.circle")
                                .font(.callout)
                                .foregroundColor(Color.insulin.opacity(0.8))
                            Text("No Data")
                                .font(.callout).fontWeight(.bold).fontDesign(.rounded)
                        }
                    }
                    /* if state.totalInsulinDisplayType == .totalDailyDose {
                     Spacer()
                     HStack {
                     Text("TDD")
                     .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                     .foregroundColor(.secondary) // ✅ Makes "TDD" text secondary
                     Text(
                     (
                     Formatter.decimalFormatterWithTwoFractionDigits
                     .string(from: (
                     state.determinationsFromPersistence.first?
                     .totalDailyDose ?? 0
                     ) as NSNumber) ??
                     "0"
                     ) +
                     NSLocalizedString(" E", comment: "Insulin unit")
                     )
                     .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                     }
                     } else {
                     Spacer()
                     HStack {
                     Text("TINS")
                     .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                     .foregroundColor(.secondary) // ✅ Makes "TINS" text secondary
                     Text(
                     "\(state.roundedTotalBolus)" +
                     NSLocalizedString(
                     " E",
                     comment: "Unit in number of units delivered (keep the space character!)"
                     )
                     )
                     .font(.subheadline).fontWeight(.bold).fontDesign(.rounded)
                     .onChange(of: state.hours) {
                     state.roundedTotalBolus = state.calculateTINS()
                     }
                     .onAppear {
                     DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                     state.roundedTotalBolus = state.calculateTINS()
                     }
                     }
                     }
                     } */
                }
            }.padding(.horizontal, 15)
        }

        @ViewBuilder func adjustmentsOverrideView(_ overrideString: String) -> some View {
            Group {
                Image(systemName: "arrow.up.arrow.down.circle")
                    .font(.title)
                    .foregroundStyle(Color.primary, Color.primary)
                VStack(alignment: .leading) {
                    Text(latestOverride.first?.name ?? "🛠️ Anpassad Override")
                        .font(.subheadline)
                        .frame(alignment: .leading)

                    Text(overrideString)
                        .font(.caption)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsTempTargetView(_ tempTargetString: String) -> some View {
            Group {
                Image(systemName: "target")
                    .font(.title)
                    .foregroundStyle(Color.loopGreen)
                VStack(alignment: .leading) {
                    Text(latestTempTarget.first?.name ?? "Temp Target")
                        .font(.subheadline)
                    Text(tempTargetString)
                        .font(.caption)
                }
            }
            .onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentsCancelView(_ cancelAction: @escaping () -> Void) -> some View {
            Image(systemName: "xmark.app")
                .font(.title)
                .onTapGesture {
                    cancelAction()
                }
        }

        @ViewBuilder func adjustmentsCancelTempTargetView() -> some View {
            Image(systemName: "xmark.app")
                .font(.title)
                .confirmationDialog(
                    "Stoppa Tillfälligt mål \"\(latestTempTarget.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopTempTargetShown,
                    titleVisibility: .visible
                ) {
                    Button("Stoppa", role: .destructive) {
                        Task {
                            guard let objectID = latestTempTarget.first?.objectID else { return }
                            await state.cancelTempTarget(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .padding(.trailing, 8)
                .onTapGesture {
                    if !latestTempTarget.isEmpty {
                        isConfirmStopTempTargetShown = true
                    }
                }
        }

        @ViewBuilder func adjustmentsCancelOverrideView() -> some View {
            Image(systemName: "xmark.app")
                .font(.title)
                .confirmationDialog(
                    "Stoppa Override \"\(latestOverride.first?.name ?? "")\"?",
                    isPresented: $isConfirmStopOverridePresented,
                    titleVisibility: .visible
                ) {
                    Button("Stoppa", role: .destructive) {
                        Task {
                            guard let objectID = latestOverride.first?.objectID else { return }
                            await state.cancelOverride(withID: objectID)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
                .padding(.trailing, 8)
                .onTapGesture {
                    if !latestOverride.isEmpty {
                        isConfirmStopOverridePresented = true
                    }
                }
        }

        @ViewBuilder func noActiveAdjustmentsView() -> some View {
            Group {
                VStack {
                    Text("Normal profil")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("100 %")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.leading, 10)

                Spacer()

                /// to ensure the same position....
                Image(systemName: "xmark.app")
                    .font(.title)
                    // clear color for the icon
                    .foregroundStyle(Color.clear)
            }.onTapGesture {
                selectedTab = 2
            }
        }

        @ViewBuilder func adjustmentView(geo: GeometryProxy) -> some View {
            //            let background = colorScheme == .dark ? Material.ultraThinMaterial.opacity(0.5) : Color.black.opacity(0.2)

            let tint = adjustmentTint
            // concurrent override + temp target: halved tint, one remaining bar per half
            let isConcurrent = overrideString != nil && tempTargetString != nil

            ZStack {
                if isConcurrent {
                    // halved tint layer the single-tint glass chrome can't express
                    HStack(spacing: 0) {
                        Color.purple.opacity(0.2)
                        Color.loopGreen.opacity(0.2)
                    }
                    .clipShape(GlassChrome.panelShape)
                }
                HStack {
                    if let overrideString = overrideString, let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsOverrideView(overrideString)

                            Spacer()

                            Divider()
                                .frame(height: geo.size.height * 0.05)
                                .padding(.horizontal, 2)

                            adjustmentsTempTargetView(tempTargetString)

                            Spacer()

                            adjustmentsCancelView({
                                if !latestTempTarget.isEmpty, !latestOverride.isEmpty {
                                    showCancelConfirmDialog = true
                                } else if !latestOverride.isEmpty {
                                    showCancelAlert = true
                                } else if !latestTempTarget.isEmpty {
                                    showCancelAlert = true
                                }
                            })
                        }
                    } else if let overrideString = overrideString {
                        adjustmentsOverrideView(overrideString)
                        Spacer()
                        adjustmentsCancelOverrideView()

                    } else if let tempTargetString = tempTargetString {
                        HStack {
                            adjustmentsTempTargetView(tempTargetString)
                            Spacer()
                            adjustmentsCancelTempTargetView()
                        }
                    } else {
                        noActiveAdjustmentsView()
                    }
                }.padding(.horizontal, 10)
                    .confirmationDialog("Adjustment to Stop", isPresented: $showCancelConfirmDialog) {
                        Button("Stop Override", role: .destructive) {
                            Task {
                                guard let objectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: objectID)
                            }
                        }
                        Button("Stoppa tillfälligt mål", role: .destructive) {
                            Task {
                                guard let objectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: objectID)
                            }
                        }
                        Button("Stoppa alla justeringar", role: .destructive) {
                            Task {
                                guard let overrideObjectID = latestOverride.first?.objectID else { return }
                                await state.cancelOverride(withID: overrideObjectID)

                                guard let tempTargetObjectID = latestTempTarget.first?.objectID else { return }
                                await state.cancelTempTarget(withID: tempTargetObjectID)
                            }
                        }
                    } message: {
                        Text("Välj vad du vill stoppa")
                    }
            } // .padding(.horizontal, 10).padding(.bottom, UIDevice.adjustPadding(min: nil, max: 10))
            // }
            .frame(height: HomeLayout.bottomPanelHeight)
            .glassPanel(
                tint: isConcurrent ? nil : tint,
                tintOpacity: 0.12,
                strokeOpacity: isConcurrent ? 0 : (tint == nil ? 0.08 : 0.30)
            )
            .overlay(
                // concurrent halves get a bicolor rim the single-tint chrome can't express
                isConcurrent
                    ? GlassChrome.panelShape.strokeBorder(
                        LinearGradient(
                            colors: [Color.purple.opacity(0.30), Color.loopGreen.opacity(0.30)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 1
                    )
                    : nil
            )
            .padding(.horizontal, 10)
        }

        @ViewBuilder func bolusView(geo _: GeometryProxy, _ progress: Decimal) -> some View {
            /// ensure that state.lastPumpBolus has a value, i.e. there is a last bolus done by the pump and not an external bolus
            /// - TRUE:  show the pump bolus
            /// - FALSE:  do not show a progress bar at all
            if let bolusTotal = state.lastPumpBolus?.bolus?.amount {
                let bolusFraction = progress * (bolusTotal as Decimal)
                let bolusString =
                    (bolusProgressFormatter.string(from: bolusFraction as NSNumber) ?? "0")
                        + String(localized: " av ", comment: "Bolus string partial message: 'x U of y U' in home view") +
                        (Formatter.decimalFormatterWithThreeFractionDigits.string(from: bolusTotal as NSNumber) ?? "0")
                        + String(localized: " E", comment: "Insulin unit")
                let bolusLabel = String(localized: "Ger bolus")

                HStack {
                    Image(systemName: "cross.vial.fill")
                        .font(.system(size: 25))

                    Spacer()

                    VStack {
                        Text(bolusLabel)
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(bolusString)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, 5)

                    Spacer()

                    Button {
                        state.showProgressView()
                        state.cancelBolus()
                    } label: {
                        Image(systemName: "xmark.app")
                            .font(.system(size: 25))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.trailing, 8)
                .frame(height: HomeLayout.bottomPanelHeight)
                .glassPanel(tint: .insulin, tintOpacity: 0.18, strokeOpacity: 0.30)
                .overlay(alignment: .bottom) {
                    // bar hugs the panel's bottom edge (the slot no longer has outer bottom padding)
                    BolusProgressBar(progress: progress)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 1)
                }
                .padding(.horizontal, 10)
            }
        }

        @ViewBuilder func alertSafetyNotificationsView(geo _: GeometryProxy) -> some View {
            ZStack {
                HStack {
                    Color.red.opacity(0.6)
                }
                .clipShape(GlassChrome.panelShape)

                HStack {
                    Spacer()
                    VStack {
                        Text("⚠️ Säkerhetsnotiser är AV")
                            .font(.headline)
                            .fontWeight(.bold)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Fixa det nu genom att aktivera notiser.")
                            .font(.footnote)
                            .fontDesign(.rounded)
                            .foregroundStyle(.white.gradient)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.leading, 5)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundColor(.white)
                        .font(.headline)
                }.padding(.horizontal, 10)
                    .padding(.trailing, 8)
                    .onTapGesture {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
            }
            .frame(height: HomeLayout.statsBannerHeight)
            .glassPanel()
            .padding(.horizontal, 10)
            .padding(.top, 0)
            .padding(.bottom, 5)
        }

        @ViewBuilder func mainViewElements(_ geo: GeometryProxy) -> some View {
            VStack(spacing: 0) {
                mealPanel(geo) // .padding(.top, UIDevice.adjustPadding(min: nil, max: 30))
                    .padding(.top, 5)
                    .padding(.bottom, 20)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if notificationsDisabled {
                            alertSafetyNotificationsView(geo: geo)
                        }
                    }
                ZStack {
                    /// glucose bobble
                    glucoseView

                    /// right panel with loop status and evBG
                    HStack {
                        Spacer()
                        rightHeaderPanel(geo)
                    }.padding(.trailing, 20)

                    /// left panel with pump related info
                    HStack {
                        pumpView
                        Spacer()
                    }.padding(.leading, 20)
                }.padding(.bottom, 20)

                mainChart(geo: geo)

                HStack {
                    tappableButton(
                        // buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
                        buttonColor: Color.secondary,
                        // label: "", // "Stats",
                        iconString: "chart.pie", // statsIconString,
                        action: { state.showModal(for: .statistics) }
                    )

                    Spacer()

                    timeIntervalButtons.padding(.top, UIDevice.adjustPadding(min: 0, max: 10))
                        .padding(.bottom, UIDevice.adjustPadding(min: 0, max: 10))

                    Spacer()

                    tappableButton(
                        // buttonColor: (colorScheme == .dark ? Color.white : Color.black).opacity(0.8),
                        buttonColor: Color.secondary,
                        // label: "", // "Info",
                        iconString: "info.circle", // "info",
                        action: { state.isLegendPresented.toggle() }
                    )
                }
                .padding(.horizontal, 20)
                .padding([.top, .bottom])

                if let progress = state.bolusProgress {
                    bolusView(geo: geo, progress)
                        .padding(.bottom, UIDevice.adjustPadding(min: nil, max: 40))
                } else {
                    adjustmentView(geo: geo).padding(.bottom, UIDevice.adjustPadding(min: nil, max: 40))
                }
            }
            .background(appState.trioBackgroundColor(for: colorScheme))
            .onReceive(
                resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
                perform: {
                    if notificationsDisabled != $0 {
                        notificationsDisabled = $0
                        if notificationsDisabled {
                            debug(.default, "notificationsDisabled")
                        }
                    }
                }
            )
        }

        @ViewBuilder func mainView() -> some View {
            GeometryReader { geo in
                mainViewElements(geo)
            }
            // no inline text input here; a stale keyboard inset must never shrink the zone budget
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .onChange(of: state.hours) {
                highlightButtons()
            }
            .onAppear {
                configureView {
                    highlightButtons()
                }
            }
            .navigationTitle("Home")
            .navigationBarHidden(true)
            .ignoresSafeArea(.keyboard)
            .blur(radius: state.isLoopStatusPresented ? 1 : 0)
            .sheet(isPresented: $state.isLoopStatusPresented) {
                LoopStatusView(state: state)
            }
            .confirmationDialog("Pump Model", isPresented: $showPumpSelection) {
                Button("Medtronic") { state.addPump(.minimed) }
                Button("All Omnipod Types") { state.addPump(.omni) }
                Button("Dana(RS/-i)") { state.addPump(.dana) }
                Button("Pump Simulator") { state.addPump(.simulator) }
            } message: { Text("Select Pump Model") }
            .sheet(isPresented: $state.setupPump) {
                if let pumpManager = state.provider.apsManager.pumpManager {
                    PumpConfig.PumpSettingsView(
                        pumpManager: pumpManager,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                } else {
                    PumpConfig.PumpSetupView(
                        pumpType: state.setupPumpType,
                        pumpInitialSettings: PumpConfig.PumpInitialSettings.default,
                        bluetoothManager: state.provider.apsManager.bluetoothManager!,
                        completionDelegate: state,
                        setupDelegate: state
                    )
                }
            }
            .sheet(isPresented: $state.isLegendPresented) {
                ChartLegendView(state: state)
            }
        }

        @ViewBuilder func tabBar() -> some View {
            if #available(iOS 26.0, *) {
                modernTabBar()
            } else {
                legacyTabBar()
            }
        }

        /// Legacy layout on the glass bar: a dead middle slot with the
        /// treatment button overlaid; the slot's selection is swallowed.
        @available(iOS 26.0, *)
        @ViewBuilder private func modernTabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: modernTabSelection) {
                    let carbsRequiredBadge: String? = carbsRequiredBadgeValue

                    NavigationStack { mainView() }
                        .tabItem { Label("", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)
                        .accessibilityLabel(Text("Main"))

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("", systemImage: historySFSymbol) }.tag(1)
                        .accessibilityLabel(Text("History"))

                    Spacer()
                        // nbsp title + empty image: invisible item that still
                        // holds a full-width slot for the overlaid button
                        .tabItem { Label {
                            Text(String(repeating: "\u{00A0}", count: 12))
                        } icon: {
                            Image(uiImage: UIImage())
                        } }
                        .tag(RootView.treatmentTabTag)

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "",
                                systemImage: "slider.horizontal.2.gobackward"
                            ) }.tag(2)
                        .accessibilityLabel(Text("Adjustments"))

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        // .environment(settingsSearchHighlight)
                        .tabItem { Label(
                            "",
                            systemImage: "gear"
                        ) }.tag(3)
                        .accessibilityLabel(Text("Settings"))
                }
                .tint(Color.tabBar)

                // fixed distance from the physical screen bottom; immune to
                // safe-area changes (keyboard, accessories)
                GeometryReader { geo in
                    treatmentButton
                        .position(x: geo.size.width / 2, y: geo.size.height - 52)
                }
                .ignoresSafeArea(.all, edges: .bottom)
            }
            .ignoresSafeArea(.container, edges: .bottom)
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .blur(radius: state.waitForSuggestion ? 8 : 0)
            .onChange(of: selectedTab) {
                if selectedTab != 3, !settingsPath.isEmpty {
                    settingsPath = NavigationPath()
                }
            }
        }

        private var modernTabSelection: Binding<Int> {
            Binding(
                get: { selectedTab },
                set: { newValue in
                    if newValue == RootView.treatmentTabTag {
                        let previous = selectedTab
                        selectedTab = newValue
                        DispatchQueue.main.async {
                            selectedTab = previous
                        }
                    } else {
                        selectedTab = newValue
                    }
                }
            )
        }

        private var treatmentButton: some View {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(Color.tabBar)
                .padding(.vertical, 2)
                .padding(.horizontal, 24)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.showModal(for: .bolus)
                }

                .accessibilityLabel(Text("Add Treatment"))
        }

        private var carbsRequiredBadgeValue: String? {
            guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                  state.showCarbsRequiredBadge
            else {
                return nil
            }
            let carbsRequiredDecimal = Decimal(carbsRequired)
            if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
            }
            return nil
        }

        @ViewBuilder private func legacyTabBar() -> some View {
            ZStack(alignment: .bottom) {
                TabView(selection: $selectedTab) {
                    let carbsRequiredBadge: String? = {
                        guard let carbsRequired = state.enactedAndNonEnactedDeterminations.first?.carbsRequired,
                              state.showCarbsRequiredBadge
                        else {
                            return nil
                        }
                        let carbsRequiredDecimal = Decimal(carbsRequired)
                        if carbsRequiredDecimal > state.settingsManager.settings.carbsRequiredThreshold {
                            let numberAsNSNumber = NSDecimalNumber(decimal: carbsRequiredDecimal)
                            return (Formatter.decimalFormatterWithTwoFractionDigits.string(from: numberAsNSNumber) ?? "") + " g"
                        }
                        return nil
                    }()

                    NavigationStack { mainView() }
                        .tabItem { Label("Hem", systemImage: "chart.xyaxis.line") }
                        .badge(carbsRequiredBadge).tag(0)

                    NavigationStack { DataTable.RootView(resolver: resolver) }
                        .tabItem { Label("History", systemImage: historySFSymbol) }.tag(1)

                    Spacer()

                    NavigationStack { Adjustments.RootView(resolver: resolver) }
                        .tabItem {
                            Label(
                                "Override",
                                // systemImage: "slider.horizontal.2.gobackward"
                                systemImage: "arrow.up.arrow.down.circle"
                            ) }.tag(2)

                    NavigationStack(path: self.$settingsPath) {
                        Settings.RootView(resolver: resolver) }
                        .tabItem { Label(
                            "Settings",
                            systemImage: "gear"
                        ) }.tag(3)
                }
                .tint(Color.tabBar)

            }.ignoresSafeArea(.keyboard, edges: .bottom).blur(radius: state.waitForSuggestion ? 8 : 0)
                .onChange(of: selectedTab) {
                    if !settingsPath.isEmpty {
                        settingsPath = NavigationPath()
                    }
                }
        }

        var body: some View {
            ZStack(alignment: .center) {
                tabBar()

                if state.waitForSuggestion {
                    CustomProgressView(text: "Uppdaterar IOB...")
                }
            }
        }
    }
}

extension UIDevice {
    public enum DeviceSize: CGFloat {
        case smallDevice = 667 // Height for 4" iPhone SE
        case largeDevice = 852 // Height for 6.1" iPhone 15 Pro
    }

    @usableFromInline static func adjustPadding(
        min: CGFloat? = nil,
        max: CGFloat? = nil
    ) -> CGFloat? {
        if UIScreen.screenHeight > UIDevice.DeviceSize.smallDevice.rawValue {
            if UIScreen.screenHeight >= UIDevice.DeviceSize.largeDevice.rawValue {
                return max
            } else {
                return min != nil ?
                    (max != nil ? max! * (UIScreen.screenHeight / UIDevice.DeviceSize.largeDevice.rawValue) : nil) : nil
            }
        } else {
            return min
        }
    }
}

extension UIScreen {
    static var screenHeight: CGFloat {
        UIScreen.main.bounds.height
    }

    static var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }
}

/// Checks if the device is using a 24-hour time format.
func is24HourFormat() -> Bool {
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    let dateString = formatter.string(from: Date())

    return !dateString.contains("AM") && !dateString.contains("PM")
}

/// Converts a duration in minutes to a formatted string (e.g., "1 hr 30 min").
func formatHrMin(_ durationInMinutes: Int) -> String {
    let hours = durationInMinutes / 60
    let minutes = durationInMinutes % 60

    switch (hours, minutes) {
    case let (0, m):
        return "\(m) min"
    case let (h, 0):
        return "\(h) hr"
    default:
        return "\(hours) hr \(minutes) min"
    }
}

// Helper function to convert a start and end hour to either 24-hour or AM/PM format
func formatTimeRange(start: String?, end: String?) -> String {
    guard let start = start, let end = end else {
        return ""
    }

    // Check if the format is 24-hour or AM/PM
    if is24HourFormat() {
        // Return the original 24-hour format
        return "\(start)-\(end)"
    } else {
        // Convert to AM/PM format using DateFormatter
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"

        if let startHour = Int(start), let endHour = Int(end) {
            let startDate = Calendar.current.date(bySettingHour: startHour, minute: 0, second: 0, of: Date()) ?? Date()
            let endDate = Calendar.current.date(bySettingHour: endHour, minute: 0, second: 0, of: Date()) ?? Date()

            // Customize the format to "2p" or "2a"
            formatter.dateFormat = "ha"
            let startFormatted = formatter.string(from: startDate).lowercased().replacingOccurrences(of: "m", with: "")
            let endFormatted = formatter.string(from: endDate).lowercased().replacingOccurrences(of: "m", with: "")

            return "\(startFormatted)-\(endFormatted)"
        } else {
            return ""
        }
    }
}
