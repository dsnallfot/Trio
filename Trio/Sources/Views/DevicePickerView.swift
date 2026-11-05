import LoopKitUI
import SwiftUI

/// A sheet for choosing a CGM or pump to set up, grouped by manufacturer.
///
/// Selection is applied by the presenter in onDismiss, after this sheet closes.
struct DevicePickerView<Selection>: View {
    let title: String
    let entries: [DeviceCatalogEntry<Selection>]
    let onSelect: (DeviceCatalogEntry<Selection>) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(AppState.self) private var appState

    private var sections: [(manufacturer: DeviceManufacturer, entries: [DeviceCatalogEntry<Selection>])] {
        DeviceCatalog.sections(for: entries)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sections, id: \.manufacturer) { section in
                    Section(header: Text(section.manufacturer.displayName)) {
                        ForEach(section.entries) { entry in
                            Button {
                                onSelect(entry)
                                dismiss()
                            } label: {
                                DevicePickerRow(entry: entry)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("devicePickerItem-\(entry.id)")
                        }
                    }
                    .listRowBackground(Color.chart)
                }
            }
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
        }
    }
}

private struct DevicePickerRow<Selection>: View {
    let entry: DeviceCatalogEntry<Selection>

    var body: some View {
        HStack(spacing: 12) {
            DeviceIconView(entry: entry)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let models = entry.supportedModelsLine {
                    Text(models)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Draws a catalog entry's artwork, falling back to its category glyph.
///
/// Every variant renders in the same fixed tile so a list mixing kit product photos with glyphs still reads as
/// one system.
private enum DeviceIconLayout {
    static let tile: CGFloat = 44
    static let cornerRadius: CGFloat = 10
    static let imageInset: CGFloat = 5
    static let glyphSize: CGFloat = 19
}

private struct DeviceIconView<Selection>: View {
    let entry: DeviceCatalogEntry<Selection>

    var body: some View {
        Group {
            if let image = entry.iconImage {
                // Tint applies only to template assets (MiniMed ships one), so photo assets are unaffected
                // and template ones harmonize with the fallback glyphs instead of rendering as a black block.
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.accentColor)
                    .padding(DeviceIconLayout.imageInset)
            } else {
                Image(systemName: entry.fallbackSymbolName)
                    .font(.system(size: DeviceIconLayout.glyphSize))
                    .foregroundColor(.accentColor)
            }
        }
        .frame(width: DeviceIconLayout.tile, height: DeviceIconLayout.tile)
        .background(
            RoundedRectangle(cornerRadius: DeviceIconLayout.cornerRadius, style: .continuous)
                .fill(Color(UIColor.tertiarySystemFill))
        )
        .accessibilityHidden(true)
    }
}
