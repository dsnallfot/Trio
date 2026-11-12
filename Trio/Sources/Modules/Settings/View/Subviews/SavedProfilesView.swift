import SwiftUI
import Swinject

struct SavedProfilesView: View {
    @StateObject private var model: SavedProfilesModel
    @State private var profileToDelete: SavedTherapyProfile?
    @State private var listError: String?
    @State private var profileToRename: SavedTherapyProfile?
    @State private var newName = ""
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    init(resolver: Resolver) {
        _model = StateObject(wrappedValue: SavedProfilesModel(resolver: resolver))
    }

    private var matchingProfileID: UUID? {
        model.current.flatMap { model.matchingProfile(for: $0)?.id }
    }

    private func profileRowBackground(_ tint: Color?) -> some View {
        Color.chart.overlay((tint ?? .clear).opacity(colorScheme == .dark ? 0.16 : 0.10))
    }

    var body: some View {
        Form {
            Section("Aktuell profil") {
                if let current = model.current {
                    NavigationLink {
                        SavedProfileReviewView(model: model, profile: current, savingCurrent: true)
                    } label: {
                        SavedProfileRowLabel(name: model.currentProfileName, profile: current, units: model.units)
                    }
                    .listRowBackground(profileRowBackground(matchingProfileID == nil ? .orange : .green))
                }
            }
            Section("Sparade profiler") {
                if model.profiles.isEmpty {
                    Text("Inga sparade profiler ännu. Spara aktuell profil för att skapa ett förval.")
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.chart)
                }
                ForEach(model.profiles) { profile in
                    NavigationLink {
                        SavedProfileReviewView(model: model, profile: profile, savingCurrent: false)
                    } label: {
                        SavedProfileRowLabel(name: profile.name, profile: profile, units: model.units)
                    }
                    .listRowBackground(profileRowBackground(profile.id == matchingProfileID ? .green : nil))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button {
                            profileToDelete = profile
                        } label: {
                            Label("Radera", systemImage: "trash")
                        }
                        .tint(.red)
                        Button {
                            newName = profile.name
                            profileToRename = profile
                        } label: {
                            Label("Byt namn", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Sparade profiler")
        .onAppear { model.reload() }
        .alert("Radera sparad profil?", isPresented: Binding(
            get: { profileToDelete != nil },
            set: { if !$0 { profileToDelete = nil } }
        ), presenting: profileToDelete) { profile in
            Button("Radera", role: .destructive) {
                listError = model.delete(profile)
            }
            Button("Avbryt", role: .cancel) {}
        } message: { profile in
            Text("Vill du verkligen radera den sparade profilen '\(profile.name)'?")
        }
        .alert("Byt namn", isPresented: Binding(
            get: { profileToRename != nil },
            set: { if !$0 { profileToRename = nil } }
        ), presenting: profileToRename) { profile in
            TextField("Profilnamn", text: $newName)
            Button("Spara") { listError = model.rename(profile, to: newName) }
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Avbryt", role: .cancel) {}
        }
        .alert("Profilhantering", isPresented: Binding(
            get: { listError != nil },
            set: { if !$0 { listError = nil } }
        )) {
            Button("OK", role: .cancel) { listError = nil }
        } message: {
            Text(listError ?? "")
        }
    }
}

private struct SavedProfileRowLabel: View {
    let name: String
    let profile: SavedTherapyProfile
    let units: GlucoseUnits
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .foregroundStyle(.primary)
            Text(profile.summary(units: units, locale: locale, multiline: true))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct SavedProfileReviewView: View {
    @ObservedObject var model: SavedProfilesModel
    let profile: SavedTherapyProfile
    let savingCurrent: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState
    @State private var showingName = false
    @State private var name = ""

    private var glucoseUnit: String { model.units == .mmolL ? "mmol/L" : "mg/dL" }

    var body: some View {
        Form {
            Section("Basalprofil") {
                ForEach(profile.basal.indices, id: \.self) { index in
                    let entry = profile.basal[index]
                    row(time(entry.minutes), "\(number(entry.rate)) E/h")
                }
                row("Total basal/dygn", "\(number(profile.totalBasal)) E/dygn")
                    .fontWeight(.semibold)
            }
            .listRowBackground(Color.chart)
            Section("Insulinkänslighet") {
                ForEach(profile.sensitivities.sensitivities.indices, id: \.self) { index in
                    let entry = profile.sensitivities.sensitivities[index]
                    row(time(entry.offset), "\(glucose(entry.sensitivity)) \(glucoseUnit)/E")
                }
            }
            .listRowBackground(Color.chart)
            Section("Insulinkvoter") {
                ForEach(profile.carbRatios.schedule.indices, id: \.self) { index in
                    let entry = profile.carbRatios.schedule[index]
                    row(time(entry.offset), "\(number(entry.ratio)) g/E")
                }
            }
            .listRowBackground(Color.chart)
            Section("Målglukos") {
                ForEach(profile.targets.targets.indices, id: \.self) { index in
                    let entry = profile.targets.targets[index]
                    let value = entry.low == entry.high ? glucose(entry.low) : "\(glucose(entry.low))–\(glucose(entry.high))"
                    row(time(entry.offset), "\(value) \(glucoseUnit)")
                }
            }
            .listRowBackground(Color.chart)
            Section {
                actionButtons
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowSeparator(.hidden)
            }
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle(savingCurrent ? "Spara aktuell profil" : "Granska '\(profile.name)'")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isActivating)
        .interactiveDismissDisabled(model.isActivating)
        .alert("Ge profilen ett namn", isPresented: $showingName) {
            TextField("Profilnamn", text: $name)
            Button("Spara") {
                if model.save(profile, name: name) { dismiss() }
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Avbryt", role: .cancel) {}
        }
        .alert("Profilhantering", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var actionButtons: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    if savingCurrent {
                        if model.canSave(profile) { showingName = true }
                    } else {
                        Task { if await model.activate(profile) { dismiss() } }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if model.isActivating {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                                .accessibilityHidden(true)
                        }
                        Text(model.isActivating ? "Aktiverar profil…" : (savingCurrent ? "Fortsätt" : "Aktivera profil"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .disabled(!profile.isValid || model.isActivating)

                Button(role: .cancel) { dismiss() } label: {
                    Text("Avbryt")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .frame(maxWidth: .infinity, minHeight: 50)
                .disabled(model.isActivating)
            }
            .controlSize(.large)
            .buttonSizing(.flexible)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func time(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func number(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 3
        return formatter.string(from: value as NSDecimalNumber) ?? value.description
    }

    private func glucose(_ value: Decimal) -> String {
        model.units == .mmolL ? value.formattedAsMmolL : number(value)
    }
}

/// Shared two-step save flow for the four therapy editors. Reads the persisted profile,
/// so the optional backup never includes the editor's pending changes.
struct TherapyProfileSaveConfirmation: ViewModifier {
    @StateObject private var profiles: SavedProfilesModel
    @Binding private var isRequested: Bool
    let saveChanges: () -> Void
    @State private var originalProfile: SavedTherapyProfile?
    @State private var name = ""
    @State private var showingName = false
    @State private var showingConfirmation = false
    @State private var showingError = false

    init(resolver: Resolver, isRequested: Binding<Bool>, saveChanges: @escaping () -> Void) {
        _profiles = StateObject(wrappedValue: SavedProfilesModel(resolver: resolver))
        _isRequested = isRequested
        self.saveChanges = saveChanges
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: isRequested) { _, requested in
                guard requested else { return }
                isRequested = false
                profiles.reload()
                originalProfile = profiles.current
                name = ""
                if profiles.currentProfileIsSaved {
                    showingConfirmation = true
                } else {
                    showingName = true
                }
            }
            .alert("Ge profilen ett namn", isPresented: $showingName) {
                TextField("Profilnamn", text: $name)
                Button("Spara") {
                    guard let originalProfile else { return }
                    if profiles.save(originalProfile, name: name) {
                        confirmChanges()
                    } else {
                        DispatchQueue.main.async { showingError = true }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Spara inte") { confirmChanges() }
            } message: {
                Text("Den befintliga profilen är inte sparad. Vill du spara den innan du tillämpar ändringarna?")
            }
            .alert("Spara ändringar?", isPresented: $showingConfirmation) {
                Button("Spara ändringar") {
                    originalProfile = nil
                    saveChanges()
                }
                Button("Avbryt", role: .cancel) { originalProfile = nil }
            } message: {
                Text("Vill du tillämpa de nya behandlingsinställningarna?")
            }
            .alert("Profilen kunde inte sparas", isPresented: $showingError) {
                Button("Försök igen") {
                    DispatchQueue.main.async { showingName = true }
                }
                Button("Avbryt", role: .cancel) { originalProfile = nil }
            } message: {
                Text(profiles.errorMessage ?? "Försök igen.")
            }
    }

    private func confirmChanges() {
        DispatchQueue.main.async { showingConfirmation = true }
    }
}
