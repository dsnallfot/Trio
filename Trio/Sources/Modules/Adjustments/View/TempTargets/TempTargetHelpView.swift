import SwiftUI

struct TempTargetHelpView: View {
    var state: Adjustments.StateModel
    var helpSheetDetent: Binding<PresentationDetent>

    var body: some View {
        NavigationStack {
            List {
                VStack(alignment: .leading, spacing: 10) {
                    Text(
                        "Ett tillfälligt mål ersätter det aktuella glukosmålet som anges i behandlingsinställningarna."
                    )
                    Text(
                        "Beroende på dina inställningar för målglukos (se Inställningar > Algoritm > Målbeteende) kan dessa tillfälliga glukosmål även öka insulinkänsligheten vid höga mål eller minska känsligheten vid låga mål."
                    )
                    Text(
                        "Du kan dessutom justera denna förändring av insulinkänsligheten oberoende av inställningen 'Halv basal träningsmål' under Algorit > Målbeteende genom att ange en anpassad insulinprocent för ett tillfälligt mål."
                    )
                    Text(
                        "För att tillfälliga mål ska kunna påverka insulinkänsligheten måste motsvarande inställning under Målbeteende, 'Högt tillfälligt mål ökar känsligheten' eller 'Lågt tillfälligt mål minskar känsligheten', vara aktiverad."
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
