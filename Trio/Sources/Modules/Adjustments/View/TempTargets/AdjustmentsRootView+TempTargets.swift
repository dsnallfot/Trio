import CoreData
import SwiftUI

extension Adjustments.RootView {
    @ViewBuilder func tempTargets() -> some View {
        if state.isTempTargetEnabled, state.activeTempTargetName.isNotEmpty {
            currentActiveAdjustment
        }
        if state.scheduledTempTargets.isNotEmpty {
            scheduledTempTargets
        }
        if state.tempTargetPresets.isNotEmpty {
            tempTargetPresets
        } else {
            defaultText
        }
    }

    private var scheduledTempTargets: some View {
        Section {
            ForEach(state.scheduledTempTargets) { tempTarget in
                tempTargetView(for: tempTarget)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        swipeActionsForTempTargets(for: tempTarget)
                    }
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("Schemalägg TIllfälligt mål")
        }
    }

    private var tempTargetPresets: some View {
        Section {
            ForEach(state.tempTargetPresets) { preset in
                tempTargetView(for: preset, showCheckmark: showTempTargetCheckmark) {
                    enactTempTargetPreset(preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActionsForTempTargets(for: preset)
                }
            }
            .onMove(perform: state.reorderTempTargets)
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $isConfirmDeletePresented,
                titleVisibility: .visible
            ) {
                deleteConfirmationButtons()
            } message: {
                deleteConfirmationMessage
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("")
        } footer: {
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text(
                    "Svep vänster för att redigera eller radera ett sparat tillfälligt mål. Håll, drag och släpp för att ändra ordning."
                )
            }
        }
    }

    private func enactTempTargetPreset(_ preset: TempTargetStored) {
        Task {
            let objectID = preset.objectID
            await state.enactTempTargetPreset(withID: objectID)
            selectedTempTargetPresetID = preset.id?.uuidString
            showTempTargetCheckmark = true

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showTempTargetCheckmark = false
            }
        }
    }

    private func swipeActionsForTempTargets(for tempTarget: TempTargetStored) -> some View {
        Group {
            Button {
                Task {
                    selectedTempTarget = tempTarget
                    isConfirmDeletePresented = true
                }
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .tint(.red)
            }
            Button(action: {
                selectedTempTarget = tempTarget
                state.showTempTargetEditSheet = true
            }, label: {
                Label("Redigera", systemImage: "pencil")
                    .tint(.blue)
            })
        }
    }

    private var deleteConfirmationTitle: String {
        "Radera det tillfälliga målet \"\(selectedTempTarget?.name ?? "")\"?"
    }

    private func deleteConfirmationButtons() -> some View {
        Group {
            if let itemToDelete = selectedTempTarget {
                Button(
                    state.currentActiveTempTarget == selectedTempTarget ? "Stoppa och radera" : "Radera",
                    role: .destructive
                ) {
                    if state.currentActiveTempTarget == selectedTempTarget {
                        Task {
                            await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                        }
                    }
                    Task {
                        await state.invokeTempTargetPresetDeletion(itemToDelete.objectID)
                    }
                    selectedTempTarget = nil
                }
            }
            Button("Cancel", role: .cancel) {
                selectedTempTarget = nil
            }
        }
    }

    private var deleteConfirmationMessage: Text? {
        if state.currentActiveTempTarget == selectedTempTarget {
            return Text("Detta tillfälliga mål är aktivt. Om du raderar det inaktiveras det också.")
        }
        return nil
    }

    var stickyStopTempTargetButton: some View {
        Button {
            Task {
                // Save cancelled Temp Targets in TempTargetRunStored Entity
                // Cancel ALL active Temp Targets
                await state.disableAllActiveTempTargets(createTempTargetRunEntry: true)
                // Update View
                state.updateLatestTempTargetConfiguration()
            }
        } label: {
            Text("Stoppa tillfälligt mål")
                .fontWeight(.semibold)
                .foregroundStyle(
                    state.isTempTargetEnabled
                        ? Color.white
                        : Color.secondary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(GlassChrome.panelShape)
        }
        .buttonStyle(.plain)
        .frame(height: 50)
        .disabled(!state.isTempTargetEnabled)
        .glassPanel(
            tint: state.isTempTargetEnabled ? Color.red : nil,
            tintOpacity: state.isTempTargetEnabled ? 0.40 : 0,
            strokeOpacity: state.isTempTargetEnabled ? 0.60 : 0.08
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 65)
    }

    private func tempTargetView(
        for tempTarget: TempTargetStored,
        showCheckmark: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let target = tempTarget.target ?? 100
        let tempTargetValue = Decimal(target as! Double.RawValue)
        let isSelected = tempTarget.id?.uuidString == selectedTempTargetPresetID
        let tempTargetHalfBasal = Decimal(
            tempTarget.halfBasalTarget as? Double
                .RawValue ?? Double(state.settingHalfBasalTarget)
        )
        let percentage = Int(
            state.computeAdjustedPercentage(usingHBT: tempTargetHalfBasal, usingTarget: tempTargetValue)
        )
        let remainingTime = tempTarget.date?.timeIntervalSinceNow ?? 0

        return ZStack(alignment: .trailing) {
            HStack {
                VStack(alignment: .leading) {
                    HStack {
                        Text(tempTarget.name ?? "")
                        Spacer()
                        if remainingTime > 0 {
                            Text("Startar om \(formattedTimeRemaining(remainingTime))")
                                .foregroundColor(colorScheme == .dark ? .orange : .accentColor)
                        }
                    }
                    HStack(spacing: 2) {
                        Text(formattedGlucose(glucose: target as Decimal))
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("i")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("\(Formatter.integerFormatter.string(from: (tempTarget.duration ?? 0) as NSNumber)!)")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Text("min")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        if state.isAdjustSensEnabled(usingTarget: tempTargetValue) {
                            Text(", \(percentage)%")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        Spacer()
                    }
                    .padding(.top, 1)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    onTap?()
                }
            }
            if showCheckmark && isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .imageScale(.large)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.green)
            } else if onTap != nil {
                Image(systemName: "line.3.horizontal")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
