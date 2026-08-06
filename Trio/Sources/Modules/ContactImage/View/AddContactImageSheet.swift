import SwiftUI

struct AddContactImageSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    @ObservedObject var state: ContactImage.StateModel

    @State private var contactName: String = ""
    @State private var hasHighContrast: Bool = true
    @State private var ringWidth: ContactImageEntry.RingWidth = .regular
    @State private var ringGap: ContactImageEntry.RingGap = .small
    @State private var layout: ContactImageLayout = .default
    @State private var primary: ContactImageValue = .glucose
    @State private var top: ContactImageValue = .none
    @State private var bottom: ContactImageValue = .trend
    @State private var ring: ContactImageLargeRing = .none
    @State private var fontSize: ContactImageEntry.FontSize = .regular
    @State private var secondaryFontSize: ContactImageEntry.FontSize = .small
    @State private var fontWeight: Font.Weight = .medium
    @State private var fontWidth: Font.Width = .standard

    private var previewEntry: ContactImageEntry {
        ContactImageEntry(
            id: UUID(),
            name: contactName, // automatically set and populated
            layout: layout,
            ring: ring,
            primary: primary,
            top: top,
            bottom: bottom,
            contactId: nil, // not needed for preview, gets set later in ContactImageStateModel via ContactImageManager
            hasHighContrast: hasHighContrast,
            ringWidth: ringWidth,
            ringGap: ringGap,
            fontSize: fontSize,
            secondaryFontSize: secondaryFontSize,
            fontWeight: fontWeight,
            fontWidth: fontWidth
        )
    }

    var body: some View {
        NavigationView {
            VStack {
                // Preview Section
                HStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(.black)
                            .foregroundColor(.white)
                            .frame(width: 100, height: 100)
                        Image(uiImage: ContactPicture.getImage(contact: previewEntry, state: state.state))
                            .resizable()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                        Circle()
                            .stroke(lineWidth: 2)
                            .foregroundColor(colorScheme == .dark ? .white : .black)
                            .frame(width: 100, height: 100)
                    }
                    Spacer()
                }
                .padding(.top, 40)
                .padding(.bottom)

                Form {
                    Section(
                        header: Text("Kontaktnamn"),
                        content: {
                            TextField("Ange namn (Valfritt)", text: $contactName)
                        }
                    ).listRowBackground(Color.chart)
                    // Layout Section
                    Section(header: Text("Stil")) {
                        Picker("Layout", selection: $layout) {
                            ForEach(ContactImageLayout.allCases, id: \.id) { layout in
                                Text(layout.displayName).tag(layout)
                            }
                        }.onChange(of: layout, { oldLayout, newLayout in
                            if oldLayout != newLayout, newLayout == .split {
                                top = .glucose
                            } else {
                                top = .none
                            }
                        })
                        Toggle("Högkontrastläge", isOn: $hasHighContrast)
                    }.listRowBackground(Color.chart)

                    // Primary Value Section
                    Section(header: Text("Visning värden")) {
                        Picker("Övre värde", selection: $top) {
                            ForEach(ContactImageValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        if layout == .default {
                            Picker("Primärt värde", selection: $primary) {
                                ForEach(ContactImageValue.allCases, id: \.id) { value in
                                    Text(value.displayName).tag(value)
                                }
                            }
                        }
                        Picker("Nedre värde", selection: $bottom) {
                            ForEach(ContactImageValue.allCases, id: \.id) { value in
                                Text(value.displayName).tag(value)
                            }
                        }

                    }.listRowBackground(Color.chart)

                    // Ring Settings Section
                    Section(header: Text("Ringinställningar")) {
                        Picker("Ringtyp", selection: $ring) {
                            ForEach(ContactImageLargeRing.allCases, id: \.self) { ring in
                                Text(ring.displayName).tag(ring)
                            }
                        }

                        if ring != .none {
                            Picker("Ringbredd", selection: $ringWidth) {
                                ForEach(ContactImageEntry.RingWidth.allCases, id: \.self) { width in
                                    Text(width.displayName).tag(width)
                                }
                            }
                            Picker("Ringgap", selection: $ringGap) {
                                ForEach(ContactImageEntry.RingGap.allCases, id: \.self) { gap in
                                    Text(gap.displayName).tag(gap)
                                }
                            }
                        }
                    }.listRowBackground(Color.chart)

                    // Font Settings Section
                    Section(header: Text("Teckensnitt")) {
                        fontSizePicker
                        if layout == .split {
                            secondaryFontSizePicker
                        }
                        fontWeightPicker
                        fontWidthPicker
                    }.listRowBackground(Color.chart)
                }

                stickySaveButton
            }
            .navigationTitle("Lägg till kontakt")
            .navigationBarTitleDisplayMode(.inline)
            .listSectionSpacing(10)
            .padding(.top, 30)
            .ignoresSafeArea(edges: .top)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(
                        action: {
                            state.isHelpSheetPresented.toggle()
                        },
                        label: {
                            Image(systemName: "questionmark.circle")
                        }
                    )
                }
            }
            .sheet(isPresented: $state.isHelpSheetPresented) {
                ContactImageHelpView(state: state, helpSheetDetent: $state.helpSheetDetent)
            }
        }
    }

    var stickySaveButton: some View {
        ZStack {
            Rectangle()
                .frame(width: UIScreen.main.bounds.width, height: 65)
                .foregroundStyle(colorScheme == .dark ? Color.bgDarkerDarkBlue : Color.white)
                .background(.thinMaterial)
                .opacity(0.8)
                .clipShape(Rectangle())

            Button(action: {
                saveNewEntry()
            }, label: {
                Text("Save").padding(10)
            })
                .frame(width: UIScreen.main.bounds.width * 0.9, alignment: .center)
                .background(Color(.systemBlue))
                .tint(.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(5)
        }
    }

    private var fontSizePicker: some View {
        Picker("Teckenstorlek", selection: $fontSize) {
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var secondaryFontSizePicker: some View {
        Picker("Sekundär teckenstorlek", selection: $secondaryFontSize) {
            ForEach(ContactImageEntry.FontSize.allCases, id: \.self) { size in
                Text(size.displayName).tag(size)
            }
        }
    }

    private var fontWeightPicker: some View {
        Picker("Teckenvikt", selection: $fontWeight) {
            ForEach(
                [Font.Weight.light, Font.Weight.regular, Font.Weight.medium, Font.Weight.bold, Font.Weight.black],
                id: \.self
            ) { weight in
                Text("\(weight.displayName)".capitalized).tag(weight)
            }
        }
    }

    private var fontWidthPicker: some View {
        Picker("Teckenbredd", selection: $fontWidth) {
            ForEach(
                [Font.Width.standard, Font.Width.expanded],
                id: \.self
            ) { width in
                Text("\(width.displayName)".capitalized).tag(width)
            }
        }
    }

    private func saveNewEntry() {
        // Save the currently previewed entry
        Task {
            await state.createAndSaveContactImage(
                entry: previewEntry,
                name: contactName.isEmpty ? "Trio \(state.contactImageEntries.count + 1)" : contactName
            )
            dismiss()
        }
    }
}
