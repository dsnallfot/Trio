import Contacts
import ContactsUI
import SwiftUI
import Swinject

extension ContactImage {
    struct RootView: BaseView {
        let resolver: Resolver
        @State var state = StateModel()
        @State private var isAddSheetPresented: Bool = false

        @Environment(\.colorScheme) var colorScheme
        @Environment(AppState.self) var appState

        var body: some View {
            Form {
                contactItemsList
            }
            .onAppear(perform: configureView)
            .navigationTitle("Kontaktkonfiguration")
            .navigationBarTitleDisplayMode(.large)
            .scrollContentBackground(.hidden)
            .background(appState.trioBackgroundColor(for: colorScheme))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isAddSheetPresented.toggle()
                    }) {
                        HStack {
                            Text(" Lägg till")
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $isAddSheetPresented) {
                AddContactImageSheet(state: state)
            }
        }

        private var contactItemsList: some View {
            List {
                if state.contactImageEntries.isEmpty {
                    Section(
                        header: Text(""),
                        content: {
                            Text("Inga sparade kontakter.")
                        }
                    ).listRowBackground(Color.chart)
                } else {
                    ForEach(state.contactImageEntries, id: \.id) { entry in
                        NavigationLink(destination: ContactImageDetailView(entry: entry, state: state)) {
                            HStack {
                                ZStack {
                                    Circle()
                                        .fill(.black)
                                        .foregroundColor(.white)
                                        .frame(width: 40, height: 40)

                                    Image(uiImage: ContactPicture.getImage(contact: entry, state: state.state))
                                        .resizable()
                                        .frame(width: 40, height: 40)
                                        .clipShape(Circle())

                                    Circle()
                                        .stroke(lineWidth: 2)
                                        .foregroundColor(colorScheme == .dark ? .white : .black)
                                        .frame(width: 40, height: 40)
                                }

                                Text("\(entry.name)")
                            }
                        }
                    }
                    .onDelete(perform: onDelete)
                }

                Section {} footer: {
                    Text(
                        "Lägg till en eller flera kontakter till dina iOS kontakter för att visa realtidsvärden från Trio på din Apple watch. Se till att ge Trio full åtkomst till dina kontakter när du tillfrågas om det av iOS.."
                    )
                    .textCase(nil)
                    .foregroundStyle(.secondary)
                }

            }.listRowBackground(Color.chart)
        }

        private func onDelete(offsets: IndexSet) {
            Task {
                for offset in offsets {
                    let entry = state.contactImageEntries[offset]
                    await state.deleteContact(entry: entry)
                }
            }
        }
    }
}
