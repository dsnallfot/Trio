import SwiftUI

struct OverrideHelpView: View {
    var state: Adjustments.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(
                            "Den här funktionen kan användas för att tillfälligt åsidosätta följande behandlingsinställningar under en valfri tidsperiod:"
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        Text("• Basalprofil")
                        Text("• Insulinkänslighet")
                        Text("• Insulinkvot")
                        Text("• Glukosmål")
                    }

                    Text(
                        "Du kan även åsidosätta Max SMB-minuter och Max UAM SMB-minuter samt välja att inaktivera SMB."
                    )

                    Text(
                        "Välj \"Starta override\" för att aktivera override direkt, eller \"Spara som förval\" för att enkelt kunna starta samma override vid ett senare tillfälle."
                    )

                    Text(
                        "Om du redigerar en aktiv override-förval kommer ändringarna även att tillämpas på den override som för närvarande körs. Om du däremot redigerar den aktiva overriden direkt påverkas inte det sparade förvalet"
                    )

                    Text(
                        "Om du använder Dynamisk ISF (utan Sigmoid) kommer en override av din ISF endast att justera de gränser som algoritmen får använda för att beräkna ISF."
                    )

                    Text(
                        "Om du använder Dynamisk ISF (med Sigmoid) kommer en override av din ISF att ändra det ISF-värde som används vid ditt målblodsocker, vilket även påverkar de ISF-värden som används vid andra glukosnivåer. Om du åsidosätter ditt glukosmål ändras även den glukosnivå där ISF återgår till ditt profilvärde. Båda dessa inställningar kan kombineras i samma override."
                    )
                }
                .listRowBackground(Color.gray.opacity(0.1))
            }
            .navigationBarTitle("Hjälp", displayMode: .inline)

            Button {
                state.isHelpSheetPresented.toggle()
            } label: {
                Text("Uppfattat!")
                    .bold()
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .center)
            }
            .buttonStyle(.bordered)
            .padding(.top)
        }
        .padding()
        .scrollContentBackground(.hidden)
        .presentationDetents(
            [.fraction(0.9), .large],
            selection: helpSheetDetent
        )
    }
}
