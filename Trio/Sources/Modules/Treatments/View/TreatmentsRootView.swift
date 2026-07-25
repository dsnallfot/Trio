import Charts
import CoreData
import LoopKitUI
import SwiftUI
import Swinject

extension Treatments {
    struct RootView: BaseView {
        enum FocusedField {
            case carbs
            case fat
            case protein
            case bolus
            case note
        }

        @FocusState private var focusedField: FocusedField?

        let resolver: Resolver

        @State var state = StateModel()

        @State private var showPresetSheet = false
        @State private var autofocus: Bool = true
        @State private var calculatorDetent = PresentationDetent.large
        @State private var pushed: Bool = false
        @State private var debounce: DispatchWorkItem?
        @State private var treatmentSwipeOffset: CGFloat = 0
        @State private var treatmentSwipeCompleted: Bool = false
        @AppStorage("TreatmentsRootView.detailedView") private var detailedView: Bool = false

        private enum Config {
            static let dividerHeight: CGFloat = 2
            static let spacing: CGFloat = 3
        }

        private enum MealTypeSelection: Hashable {
            case normal
            case fattyMeal
            case superBolus
        }

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        private var formatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 2
            return formatter
        }

        private var mealFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.maximumFractionDigits = 1
            return formatter
        }

        private var gluoseFormatter: NumberFormatter {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            if state.units == .mmolL {
                formatter.minimumFractionDigits = 1
                formatter.maximumFractionDigits = 1
            } else { formatter.maximumFractionDigits = 0 }
            return formatter
        }

        private var fractionDigits: Int {
            if state.units == .mmolL {
                return 1
            } else { return 0 }
        }

        private var mealTypeSelection: Binding<MealTypeSelection> {
            Binding(
                get: {
                    if state.useFattyMealCorrectionFactor {
                        return .fattyMeal
                    }
                    if state.useSuperBolus {
                        return .superBolus
                    }
                    return .normal
                },
                set: { selection in
                    switch selection {
                    case .normal:
                        state.useFattyMealCorrectionFactor = false
                        state.useSuperBolus = false
                    case .fattyMeal:
                        state.useFattyMealCorrectionFactor = true
                        state.useSuperBolus = false
                    case .superBolus:
                        state.useFattyMealCorrectionFactor = false
                        state.useSuperBolus = true
                    }

                    Task {
                        state.insulinCalculated = await state.calculateInsulin()
                    }
                }
            )
        }

        /// Handles macro input (carb, fat, protein) in a debounced fashion.
        func handleDebouncedInput() {
            debounce?.cancel()
            debounce = DispatchWorkItem { [self] in
                Task {
                    state.insulinCalculated = await state.calculateInsulin()
                    await state.updateForecasts()
                }
            }
            if let debounce = debounce {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: debounce)
            }
        }

        @ViewBuilder private func proteinAndFat() -> some View {
            HStack {
                HStack {
                    Text("Protein")

                    TextFieldWithToolBar(
                        text: $state.protein,
                        placeholder: "0",
                        keyboardType: .numberPad,
                        numberFormatter: mealFormatter,
                        previousTextField: { focusOnPreviousTextField(index: 3) },
                        nextTextField: { focusOnNextTextField(index: 3) }
                    ).focused($focusedField, equals: .protein)
                    Text("g").foregroundColor(.secondary)
                }

                Divider().foregroundStyle(.primary).fontWeight(.bold).frame(width: 10)

                HStack {
                    Text("Fat")
                    TextFieldWithToolBar(
                        text: $state.fat,
                        placeholder: "0",
                        keyboardType: .numberPad,
                        numberFormatter: mealFormatter,
                        previousTextField: { focusOnPreviousTextField(index: 2) },
                        nextTextField: { focusOnNextTextField(index: 2) }
                    ).focused($focusedField, equals: .fat)
                    Text("g").foregroundColor(.secondary)
                }
            }
        }

        @ViewBuilder private func carbsTextField() -> some View {
            HStack {
                Text("Carbs")
                Spacer()
                TextFieldWithToolBar(
                    text: $state.carbs,
                    placeholder: "0",
                    keyboardType: .numberPad,
                    numberFormatter: mealFormatter,
                    previousTextField: { focusOnPreviousTextField(index: 1) },
                    nextTextField: { focusOnNextTextField(index: 1) }
                ).focused($focusedField, equals: .carbs)
                    .onChange(of: state.carbs) {
                        handleDebouncedInput()
                    }
                Text("g").foregroundColor(.secondary)
            }
        }

        private var focusOrder: [FocusedField] {
            if detailedView, state.useFPUconversion {
                return [.carbs, .protein, .fat, .note, .bolus]
            }
            return [.carbs, .note, .bolus]
        }

        func focusOnPreviousTextField(index: Int) {
            guard let currentField = field(for: index), let currentIndex = focusOrder.firstIndex(of: currentField) else {
                return
            }
            let previousIndex = focusOrder.index(before: currentIndex)
            focusedField = focusOrder.indices.contains(previousIndex) ? focusOrder[previousIndex] : focusOrder.last
        }

        func focusOnNextTextField(index: Int) {
            guard let currentField = field(for: index), let currentIndex = focusOrder.firstIndex(of: currentField) else {
                return
            }
            let nextIndex = focusOrder.index(after: currentIndex)
            focusedField = focusOrder.indices.contains(nextIndex) ? focusOrder[nextIndex] : focusOrder.first
        }

        private func field(for index: Int) -> FocusedField? {
            switch index {
            case 1:
                return .carbs
            case 2:
                return .fat
            case 3:
                return .protein
            case 4:
                return .bolus
            case 5:
                return .note
            default:
                return nil
            }
        }

        var body: some View {
            ZStack(alignment: .center) {
                VStack {
                    List {
                        Section {
                            ForecastChart(state: state)
                                .padding(.vertical)
                        }.listRowBackground(Color.chart)

                        Section {
                            carbsTextField()

                            if detailedView, state.useFPUconversion {
                                proteinAndFat()
                            }

                            if detailedView {
                                // Time
                                HStack {
                                    // Semi-hacky workaround to make sure the List renders the horizontal divider properly between the `Time` and `Note` rows within the Section
                                    HStack {
                                        Text("")
                                        Image(systemName: "clock").padding(.leading, -7)
                                    }

                                    Spacer()
                                    if !pushed {
                                        Button {
                                            pushed = true
                                        } label: { Text("Now") }.buttonStyle(.borderless).foregroundColor(.secondary)
                                            .padding(.trailing, 5)
                                    } else {
                                        Button { state.date = state.date.addingTimeInterval(-15.minutes.timeInterval) }
                                        label: { Image(systemName: "minus.circle") }.tint(.blue).buttonStyle(.borderless)

                                        DatePicker(
                                            "Time",
                                            selection: $state.date,
                                            displayedComponents: [.hourAndMinute]
                                        ).controlSize(.mini)
                                            .labelsHidden()
                                        Button {
                                            state.date = state.date.addingTimeInterval(15.minutes.timeInterval)
                                        }
                                        label: { Image(systemName: "plus.circle") }.tint(.blue).buttonStyle(.borderless)
                                    }
                                }
                            }

                            // Notes
                            HStack {
                                Image(systemName: "square.and.pencil")
                                TextFieldWithToolBarStringAndChevrons(
                                    text: $state.note,
                                    placeholder: "Notering",
                                    maxLength: 25,
                                    previousTextField: { focusOnPreviousTextField(index: 5) },
                                    nextTextField: { focusOnNextTextField(index: 5) }
                                )
                                .focused($focusedField, equals: .note)
                            }
                        }.listRowBackground(Color.chart)

                        Section {
                            if detailedView {
                                if state.fattyMeals || state.sweetMeals {
                                    Picker("Meal Type", selection: mealTypeSelection) {
                                        Text("Normal dos").tag(MealTypeSelection.normal)
                                        if state.fattyMeals {
                                            Text("Fatty Meal").tag(MealTypeSelection.fattyMeal)
                                        }
                                        if state.sweetMeals {
                                            Text("Super Bolus").tag(MealTypeSelection.superBolus)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                            }

                            HStack {
                                HStack {
                                    Text("Recommendation")
                                    Button(action: {
                                        state.showInfo.toggle()
                                    }, label: {
                                        Image(systemName: "info.circle")
                                    })
                                        .foregroundStyle(.blue)
                                        .buttonStyle(PlainButtonStyle())
                                }
                                Spacer()
                                Button {
                                    state.amount = state.insulinCalculated
                                } label: {
                                    HStack {
                                        Text(
                                            formatter
                                                .string(from: Double(state.insulinCalculated) as NSNumber) ?? ""
                                        )

                                        Text(
                                            NSLocalizedString(
                                                " U",
                                                comment: "Unit in number of units delivered (keep the space character!)"
                                            )
                                        ).foregroundColor(.secondary)
                                    }
                                }
                                .disabled(state.insulinCalculated == 0 || state.amount == state.insulinCalculated)
                                .buttonStyle(.bordered).padding(.trailing, -10)
                            }

                            HStack {
                                Text("Bolus")
                                Spacer()
                                TextFieldWithToolBar(
                                    text: $state.amount,
                                    placeholder: "0",
                                    textColor: colorScheme == .dark ? .white : .blue,
                                    maxLength: 5,
                                    numberFormatter: formatter,
                                    previousTextField: { focusOnPreviousTextField(index: 4) },
                                    nextTextField: { focusOnNextTextField(index: 4) }
                                ).focused($focusedField, equals: .bolus)
                                    .onChange(of: state.amount) {
                                        Task {
                                            await state.updateForecasts()
                                        }
                                    }
                                Text(" U").foregroundColor(.secondary)
                            }

                            if detailedView {
                                HStack {
                                    Text("External Insulin")
                                    Spacer()
                                    Toggle("", isOn: $state.externalInsulin).toggleStyle(Checkbox())
                                }
                            }
                        }.listRowBackground(Color.chart)

                        treatmentButton
                    }
                    .listSectionSpacing(sectionSpacing)
                }
                .blur(radius: state.waitForSuggestion ? 5 : 0)

                if state.waitForSuggestion {
                    CustomProgressView(text: progressText.rawValue)
                }
            }
            .padding(.top)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden).background(appState.trioBackgroundColor(for: colorScheme))
            .blur(radius: state.showInfo ? 3 : 0)
            .navigationTitle("Treatments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        state.hideModal()
                    } label: {
                        Text("Close")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        detailedView.toggle()
                        if !detailedView {
                            pushed = false
                            state.externalInsulin = false
                            state.useFattyMealCorrectionFactor = false
                            state.useSuperBolus = false
                            focusedField = nil
                        }
                    } label: {
                        Image(systemName: detailedView ? "text.badge.minus" : "text.badge.plus")
                    }
                }
                if state.displayPresets {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: {
                            showPresetSheet = true
                        }, label: {
                            HStack {
                                Text("Förval")
                                Image(systemName: "plus")
                            }
                        })
                    }
                }
            })
            .onAppear {
                configureView {
                    state.isActive = true
                    Task { @MainActor in
                        state.insulinCalculated = await state.calculateInsulin()
                    }
                }
            }
            .onDisappear {
                state.isActive = false
                state.addButtonPressed = false
            }
            .sheet(isPresented: $state.showInfo) {
                PopupView(state: state)
                    .presentationDetents([.fraction(0.9), .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showPresetSheet, onDismiss: {
                showPresetSheet = false
            }) {
                MealPresetView(state: state)
            }
        }

        var progressText: ProgressText {
            switch (state.amount > 0, state.carbs > 0) {
            case (true, true):
                return .updatingIOBandCOB
            case (false, true):
                return .updatingCOB
            case (true, false):
                return .updatingIOB
            default:
                return .updatingTreatments
            }
        }

        var treatmentButton: some View {
            var treatmentButtonBackground = Color(.systemBlue)
            if limitExceeded {
                treatmentButtonBackground = Color(.systemRed)
            } else if disableTaskButton {
                treatmentButtonBackground = Color(.systemGray)
            }

            return swipeTreatmentButton(background: treatmentButtonBackground)
                .disabled(disableTaskButton)
                .listRowBackground(Color.clear)
                .listRowInsets(
                    EdgeInsets(
                        top: 6,
                        leading: 0,
                        bottom: 6,
                        trailing: 0
                    )
                )
                .listRowSeparator(.hidden)
                .shadow(radius: 3)
        }

        private func swipeTreatmentButton(background: Color) -> some View {
            GeometryReader { geometry in
                let buttonHeight: CGFloat = 52
                let handleSize: CGFloat = 46
                let handlePadding: CGFloat = 3
                let maxOffset = max(0, geometry.size.width - handleSize - handlePadding * 2)
                let activationOffset = maxOffset * 0.82
                let isWaitingForBolus = state.isBolusInProgress && state
                    .amount > 0 && !state.externalInsulin && (state.carbs == 0 || state.fat == 0 || state.protein == 0)

                ZStack(alignment: .leading) {
                    HStack {
                        if isWaitingForBolus {
                            ProgressView()
                        }
                        taskButtonLabel
                    }
                    .font(.headline)
                    .foregroundStyle(Color.white.opacity(disableTaskButton ? 0.7 : 1))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: buttonHeight)

                    Circle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .overlay(
                            Image(systemName: treatmentSwipeCompleted ? "checkmark" : "chevron.right")
                                .font(.headline)
                                .foregroundStyle(treatmentSwipeCompleted ? Color.green : background)
                                .contentTransition(.symbolEffect(.replace))
                        )
                        .offset(x: handlePadding + treatmentSwipeOffset)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard !disableTaskButton else { return }
                                    treatmentSwipeOffset = min(max(0, value.translation.width), maxOffset)
                                }
                                .onEnded { _ in
                                    guard !disableTaskButton else {
                                        treatmentSwipeOffset = 0
                                        treatmentSwipeCompleted = false
                                        return
                                    }

                                    if treatmentSwipeOffset >= activationOffset {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                            treatmentSwipeOffset = maxOffset
                                        }
                                        withAnimation(.easeOut(duration: 0.12)) {
                                            treatmentSwipeCompleted = true
                                        }

                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            state.invokeTreatmentsTask()
                                        }

                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            withAnimation(.easeOut(duration: 0.12)) {
                                                treatmentSwipeCompleted = false
                                            }

                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                                    treatmentSwipeOffset = 0
                                                }
                                            }
                                        }
                                    } else {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                            treatmentSwipeOffset = 0
                                            treatmentSwipeCompleted = false
                                        }
                                    }
                                }
                        )
                }
                .frame(height: buttonHeight)
                .frame(maxWidth: .infinity)
                .background(background)
                .clipShape(Capsule())
            }
            .frame(height: 52)
        }

        private var taskButtonLabel: some View {
            if pumpBolusLimitExceeded {
                return Text("Maxgräns bolus: \(state.maxBolus.description) E")
            } else if externalBolusLimitExceeded {
                return Text("Maxgräns extern bolus: \(state.maxExternal.description) E")
            } else if carbLimitExceeded {
                return Text("Maxgräns kh: \(state.maxCarbs.description) g")
            } else if fatLimitExceeded {
                return Text("Maxgräns fett: \(state.maxFat.description) g")
            } else if proteinLimitExceeded {
                return Text("Maxgräns protein: \(state.maxProtein.description) g")
            }

            let hasInsulin = state.amount > 0
            let hasCarbs = state.carbs > 0
            let hasFatOrProtein = state.fat > 0 || state.protein > 0
            let bolusString = state.externalInsulin ? "externt Insulin" : "ge bolus"

            if state.isBolusInProgress && hasInsulin && !state.externalInsulin && (!hasCarbs || !hasFatOrProtein) {
                return Text("Bolus In Progress...")
            }

            switch (hasInsulin, hasCarbs, hasFatOrProtein) {
            case (true, true, true):
                return Text("Logga måltid & \(bolusString)")
            case (true, true, false):
                return Text("Logga kh & \(bolusString)")
            case (true, false, true):
                return Text("Logga FPU & \(bolusString)")
            case (true, false, false):
                return Text(state.externalInsulin ? "Log External Insulin" : "Enact Bolus")
            case (false, true, true):
                return Text("Log Meal")
            case (false, true, false):
                return Text("Log Carbs")
            case (false, false, true):
                return Text("Log FPU")
            default:
                return Text("Continue Without Treatment")
            }
        }

        private var pumpBolusLimitExceeded: Bool {
            !state.externalInsulin && state.amount > state.maxBolus
        }

        private var externalBolusLimitExceeded: Bool {
            state.externalInsulin && state.amount > state.maxExternal
        }

        private var carbLimitExceeded: Bool {
            state.carbs > state.maxCarbs
        }

        private var fatLimitExceeded: Bool {
            state.fat > state.maxFat
        }

        private var proteinLimitExceeded: Bool {
            state.protein > state.maxProtein
        }

        private var limitExceeded: Bool {
            pumpBolusLimitExceeded || externalBolusLimitExceeded || carbLimitExceeded || fatLimitExceeded || proteinLimitExceeded
        }

        private var disableTaskButton: Bool {
            (
                state.isBolusInProgress && state
                    .amount > 0 && !state.externalInsulin && (state.carbs == 0 || state.fat == 0 || state.protein == 0)
            ) || state
                .addButtonPressed || limitExceeded
        }
    }

    struct DividerDouble: View {
        var body: some View {
            VStack(spacing: 2) {
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(.gray.opacity(0.65))
            }
            .frame(height: 4)
            .padding(.vertical)
        }
    }

    struct DividerCustom: View {
        var body: some View {
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.gray.opacity(0.65))
                .padding(.vertical)
        }
    }
}

// fix iOS 15 bug
struct ActivityIndicator: UIViewRepresentable {
    @Binding var isAnimating: Bool
    let style: UIActivityIndicatorView.Style

    func makeUIView(context _: UIViewRepresentableContext<ActivityIndicator>) -> UIActivityIndicatorView {
        UIActivityIndicatorView(style: style)
    }

    func updateUIView(_ uiView: UIActivityIndicatorView, context _: UIViewRepresentableContext<ActivityIndicator>) {
        isAnimating ? uiView.startAnimating() : uiView.stopAnimating()
    }
}
