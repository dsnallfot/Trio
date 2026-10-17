import Foundation

import SwiftUI
import Swinject

struct ReviewInsulinActionView: BaseView {
    var resolver: any Swinject.Resolver

    @ObservedObject var state: NightscoutConfig.StateModel

    @State private var shouldDisplayHint: Bool = false
    @State private var hintDetent = PresentationDetent.large
    @State private var selectedVerboseHint: AnyView?
    @State private var hintLabel: String?
    @State private var decimalPlaceholder: Decimal = 0.0
    @State private var booleanPlaceholder: Bool = false

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            SettingInputSection(
                decimalValue: $state.importedInsulinActionCurve,
                booleanValue: $booleanPlaceholder,
                shouldDisplayHint: $shouldDisplayHint,
                selectedVerboseHint: Binding(
                    get: { selectedVerboseHint },
                    set: {
                        selectedVerboseHint = $0.map { AnyView($0) }
                        hintLabel = "Insulinets verkningstid"
                    }
                ),
                units: state.units,
                type: .decimal("dia"),
                label: "Insulinets verkningstid",
                miniHint: "Hur många timmar insulinet är aktivt i kroppen.",
                verboseHint:
                VStack(alignment: .leading, spacing: 10) {
                    Text("Standard: 10 timmar").bold()

                    Text(
                        "Insulinets verkningstid (DIA) anger hur länge insulinet fortsätter att sänka glukosnivån efter att en dos har givits."
                    )

                    Text(
                        "Detta hjälper systemet att beräkna aktivt insulin (IOB) på ett korrekt sätt och minskar risken för över- eller underkorrigering genom att ta hänsyn till den sista delen av insulinets effekt."
                    )

                    Text(
                        "Tips: Det är oftast bättre att använda en 'Anpassad topptid' än att ändra insulinets verkningstid (DIA)."
                    )
                },
                headerText: "Granska importerad DIA"
            )
        }
        .sheet(isPresented: $shouldDisplayHint) {
            SettingInputHintView(
                hintDetent: $hintDetent,
                shouldDisplayHint: $shouldDisplayHint,
                hintLabel: hintLabel ?? "",
                hintText: selectedVerboseHint ?? AnyView(EmptyView()),
                sheetTitle: "Hjälp"
            )
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .onAppear(perform: configureView)
        .navigationTitle("Insulinets verkningstid")
        .navigationBarTitleDisplayMode(.automatic)
        .onDisappear {
            state.saveReviewedInsulinAction()
        }
    }
}
