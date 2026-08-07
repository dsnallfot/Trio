import CoreData
import SwiftUI

extension Adjustments.RootView {
    @ViewBuilder func overrides() -> some View {
        if state.isOverrideEnabled, state.activeOverrideName.isNotEmpty {
            currentActiveAdjustment
        }
        if state.overridePresets.isNotEmpty {
            overridePresets
        } else {
            defaultText
        }
    }

    var overridePresets: some View {
        Section {
            ForEach(state.overridePresets) { preset in
                overridesView(for: preset, showCheckMark: showOverrideCheckmark) {
                    enactOverridePreset(preset)
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    swipeActionsForOverrides(for: preset)
                }
            }
            .onMove(perform: state.reorderOverride)
            .confirmationDialog(
                "Radera den sparade overriden \"\(selectedOverride?.name ?? "")\"?",
                isPresented: $isConfirmDeletePresented,
                titleVisibility: .visible
            ) {
                if let itemToDelete = selectedOverride {
                    Button(
                        state.currentActiveOverride == selectedOverride ? "Stoppa och radera" : "Radera",
                        role: .destructive
                    ) {
                        if state.currentActiveOverride == selectedOverride {
                            Task {
                                // Save cancelled Override in OverrideRunStored Entity
                                // Cancel ALL active Override
                                await state.disableAllActiveOverrides(createOverrideRunEntry: true)
                            }
                        }
                        // Perform the delete action
                        Task {
                            await state.invokeOverridePresetDeletion(itemToDelete.objectID)
                        }
                        // Reset the selected item after deletion
                        selectedOverride = nil
                    }
                }
                Button("Cancel", role: .cancel) {
                    // Dismiss the dialog without action
                    selectedOverride = nil
                }
            } message: {
                if state.currentActiveOverride == selectedOverride {
                    Text(
                        state
                            .currentActiveOverride == selectedOverride ?
                            "Denna override är aktiv. Om du raderar den inaktiveras den också." : ""
                    )
                }
            }
            .listRowBackground(Color.chart)
        } header: {
            Text("")
        } footer: {
            HStack {
                Image(systemName: "hand.draw.fill").foregroundStyle(.primary)
                Text("Svep vänster för att redigera eller radera en sparad override. Håll, drag och släpp för att ändra ordning.")
            }
        }
    }

    func enactOverridePreset(_ preset: OverrideStored) {
        Task {
            let objectID = preset.objectID
            await state.enactOverridePreset(withID: objectID)
            state.hideModal()
            selectedOverridePresetID = preset.id
            showOverrideCheckmark = true

            // Deactivate checkmark after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showOverrideCheckmark = false
            }
        }
    }

    func swipeActionsForOverrides(for preset: OverrideStored) -> some View {
        Group {
            Button(role: .none) {
                selectedOverride = preset
                isConfirmDeletePresented = true
            } label: {
                Label("Delete", systemImage: "trash.fill")
                    .tint(.red)
            }
            Button(action: {
                // Set the selected Override to the chosen Preset and pass it to the Edit Sheet
                selectedOverride = preset
                state.showOverrideEditSheet = true
            }, label: {
                Label("Edit", systemImage: "pencil")
                    .tint(.blue)
            })
        }
    }

    var overrideLabelDivider: some View {
        Divider()
            .frame(width: 1, height: 20)
    }

    var stickyStopOverrideButton: some View {
        Button {
            Task {
                // Save cancelled Override in OverrideRunStored Entity
                // Cancel ALL active Override
                await state.disableAllActiveOverrides(createOverrideRunEntry: true)
            }
        } label: {
            Text("Stoppa override")
                .fontWeight(.semibold)
                .foregroundStyle(
                    state.isOverrideEnabled
                        ? Color.white
                        : Color.secondary
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(GlassChrome.panelShape)
        }
        .buttonStyle(.plain)
        .frame(height: 50)
        .disabled(!state.isOverrideEnabled)
        .glassPanel(
            tint: state.isOverrideEnabled ? Color.red : nil,
            tintOpacity: state.isOverrideEnabled ? 0.40 : 0,
            strokeOpacity: state.isOverrideEnabled ? 0.50 : 0.08
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(height: 65)
    }

    @ViewBuilder func overridesView(
        for preset: OverrideStored,
        showCheckMark _: Bool = false,
        onTap: (() -> Void)? = nil
    ) -> some View {
        let isSelected = preset.id == selectedOverridePresetID
        let name = preset.name ?? ""
        let indefinite = preset.indefinite
        let duration = preset.duration?.decimalValue ?? Decimal(0)
        let percentage = preset.percentage
        let smbMinutes = preset.smbMinutes?.decimalValue ?? Decimal(0)
        let uamMinutes = preset.uamMinutes?.decimalValue ?? Decimal(0)

        let target: String = {
            guard let targetValue = preset.target, targetValue != 0 else { return "" }
            return state.units == .mgdL ? targetValue.description : targetValue.decimalValue.formattedAsMmolL
        }()

        let targetString = target.isEmpty ? "" : "\(target) \(state.units.rawValue)"

        let durationString = indefinite ? " ∞ " : "\(state.formatHrMin(Int(duration)))"

        let scheduledSMBString: String = {
            guard preset.smbIsScheduledOff, preset.start != preset.end else { return "" }
            return " \(formatTimeRange(start: preset.start?.stringValue, end: preset.end?.stringValue))"
        }()

        let smbString: String = {
            guard preset.smbIsOff || preset.smbIsScheduledOff else { return "" }
            return "SMB AV\(scheduledSMBString)"
        }()

        let maxSmbMinsString: String = {
            guard smbMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  smbMinutes != state.defaultSmbMinutes else { return "" }
            return "\(smbMinutes.formatted()) min SMB"
        }()

        let maxUamMinsString: String = {
            guard uamMinutes != 0, preset.advancedSettings, !preset.smbIsOff,
                  uamMinutes != state.defaultUamMinutes else { return "" }
            return "\(uamMinutes.formatted()) min UAM"
        }()

        let isfAndCrString: String = {
            switch (preset.isfAndCr, preset.isf, preset.cr) {
            case (_, true, true),
                 (true, _, _):
                return " ISF/CR"
            case (false, true, false):
                return " ISF"
            case (false, false, true):
                return " CR"
            default:
                return ""
            }
        }()

        let percentageString = percentage != 100 ? "\(Int(percentage))%\(isfAndCrString)" : ""

        // Combine all labels into a single array, filtering out empty strings
        let labels: [String] = [
            percentageString,
            durationString,
            targetString,
            smbString,
            maxSmbMinsString,
            maxUamMinsString
        ].filter { !$0.isEmpty }

        if !name.isEmpty {
            ZStack(alignment: .trailing) {
                HStack {
                    VStack {
                        HStack {
                            Text(name)
                            Spacer()
                        }
                        HStack(spacing: 5) {
                            ForEach(labels, id: \.self) { label in
                                Text(label)
                                /* if label != labels.last { // Add divider between labels
                                     overrideLabelDivider
                                 } */
                            }
                            Spacer()
                        }
                        .padding(.top, 1)
                        .foregroundColor(.secondary)
                        .font(.caption)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?()
                    }
                }
                // show checkmark to indicate if the preset was actually pressed
                if showOverrideCheckmark && isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .imageScale(.large)
                        .fontWeight(.bold)
                        .foregroundStyle(Color.green)
                } else {
                    Image(systemName: "line.3.horizontal")
                        .imageScale(.medium)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
