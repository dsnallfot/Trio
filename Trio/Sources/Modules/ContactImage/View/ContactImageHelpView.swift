import SwiftUI

struct ContactImageHelpView: View {
    var state: ContactImage.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                DefinitionRow(
                    term: "Hur Trio hanterar kontaktbilder",
                    definition: Text(
                        "Trio ger automatiskt varje kontaktbild du skapar ett namn, till exempel \"Trio 1\", och skapar en motsvarande kontakt i iOS Kontakter. Tryck på knappen \"Spara\" längst ned för att spara din anpassade kontaktbild."
                    )
                ).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(
                    term: "Förhandsgranska kontaktbild",
                    definition: Text(
                        "Högst upp på skärmen visas en förhandsvisning av din kontaktbild i realtid. Ändringar av stil, layout eller inställningar visas omedelbart i förhandsvisningen."
                    )
                ).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: "Anpassa stil och layout", definition: VStack(alignment: .leading) {
                    Text("Välj mellan flera olika layouter med hjälp av layoutväljaren under avsnittet \"Stil\".")

                    Text("Aktivera Högkontrastläge för bättre läsbarhet under vissa förhållanden.")

                    Text("Tillgängliga layouter:")

                    Text(
                        "• Standard: Visar ett primärt värde med upp till två mindre värden (\"Övre\" och \"Nedre\") ovanför respektive under det."
                    )

                    Text("• Delad: Delar upp värdena i två separata områden av samma storlek.")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: "Ange visningsvärden", definition: VStack(alignment: .leading) {
                    Text(
                        "Välj vilka värden som ska visas på kontaktbilden (t.ex. glukos, trend eller inget) för de tillgängliga platserna:"
                    )

                    Text("• Ingen: Inget värde visas.")

                    Text("• Glukosvärde: Aktuellt glukosvärde från CGM.")

                    Text("• Prognostiserat glukos: Glukosvärde som beräknats av oref-algoritmen.")

                    Text("• Glukosförändring: Förändringen av glukosvärdet.")

                    Text("• Glukostrend: Riktningen på glukosförändringen.")

                    Text("• COB: Kolhydrater ombord.")

                    Text("• IOB: Aktivt insulin.")

                    Text("• Loopstatus: Visar den aktuella loopstatusen (grön, gul eller röd).")

                    Text("• Tid för senaste loop: Tidpunkten då algoritmen senast kördes.")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: "Justera ringinställningar", definition: VStack(alignment: .leading) {
                    Text("Lägg till visuella ringar runt kontaktbilden för att framhäva information.")

                    Text("Finjustera ringens bredd och mellanrum så att den passar dina önskemål.")

                    Text("Tillgängliga ringar:")

                    Text("• Dold: Ingen ring visas.")

                    Text("• Loopstatus: Visar den aktuella loopstatusen (grön, gul eller röd).")
                }).listRowBackground(Color.gray.opacity(0.1))

                DefinitionRow(term: "Anpassa teckensnitt", definition: VStack(alignment: .leading) {
                    Text("Välj teckenstorlek, teckenvikt och teckenbredd för att anpassa utseendet:")

                    Text("• Teckenstorlek: Justera storleken på huvudtexten.")

                    Text("• Sekundär teckenstorlek: Justera textstorleken för värden i delade layouter.")

                    Text("• Teckenvikt: Styr hur fet texten ska vara.")

                    Text("• Teckenbredd: Välj mellan normal eller utökad teckenbredd.")
                }).listRowBackground(Color.gray.opacity(0.1))
            }
            .scrollContentBackground(.hidden)
            .navigationBarTitle("Hjälp", displayMode: .inline)

            Button { state.isHelpSheetPresented.toggle() }
            label: { Text("Uppfattat!").bold().frame(maxWidth: .infinity, minHeight: 30, alignment: .center) }
                .buttonStyle(.bordered)
                .padding(.top)
        }
        .padding()
        .presentationDetents(
            [.fraction(0.9), .large],
            selection: helpSheetDetent
        )
    }
}
