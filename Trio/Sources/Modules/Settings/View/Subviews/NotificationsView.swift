import Foundation
import LoopKitUI
import SwiftUI
import Swinject

struct NotificationsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel
    @State var notificationsDisabled = false
    @State var showAlert = false
    @State private var shouldDisplayHint: Bool = false
    @State var hintDetent = PresentationDetent.large
    @State var selectedVerboseHint: AnyView? = AnyView(
        VStack(alignment: .leading, spacing: 10) {
            Text(
                "Notiser ger dig viktig information från Trio utan att du behöver öppna appen."
            )

            Text(
                "Se till att dessa är aktiverade i telefonens inställningar så att du kan ta emot notiser från Trio, kritiska varningar och tidskänsliga notiser."
            )
        }
    )
    @State var hintLabel: String? = "Hantera iOS-inställningar"

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        List {
            Section(
                header: Text("Hantera iOS-inställningar"),
                content: {
                    manageNotifications
                }
            )
            .listRowBackground(Color.chart)

            Section {
                VStack {
                    notificationsEnabledStatus

                    HStack(alignment: .top) {
                        Text(
                            "Notiser ger dig viktig information från Trio utan att du behöver öppna appen."
                        )
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)

                        Spacer()

                        Button(
                            action: {
                                hintLabel = "Hantera iOS-inställningar"

                                selectedVerboseHint = AnyView(
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(
                                            "Notiser ger dig viktig information från Trio utan att du behöver öppna appen."
                                        )

                                        Text(
                                            "Se till att dessa är aktiverade i telefonens inställningar så att du kan ta emot notiser från Trio, kritiska varningar och tidskänsliga notiser."
                                        )
                                    }
                                )

                                shouldDisplayHint.toggle()
                            },
                            label: {
                                HStack {
                                    Image(systemName: "questionmark.circle")
                                }
                            }
                        )
                        .buttonStyle(BorderlessButtonStyle())
                    }
                    .padding(.top)
                }
                .padding(.bottom)
            }
            .listRowBackground(Color.chart)

            Section(
                header: Text("Notiscenter"),
                content: {
                    Text("Trio-notiser")
                        .navigationLink(to: .glucoseNotificationSettings, from: self)

                    if #available(iOS 16.2, *) {
                        Text("Liveaktivitet")
                            .navigationLink(to: .liveActivitySettings, from: self)
                    }

                    Text("Kalenderhändelser")
                        .navigationLink(to: .calendarEventSettings, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .listSectionSpacing(sectionSpacing)
        .onReceive(
            resolver.resolve(AlertPermissionsChecker.self)!.$notificationsDisabled,
            perform: {
                if notificationsDisabled != $0 {
                    notificationsDisabled = $0

                    if notificationsDisabled {
                        showAlert = true
                    }
                }
            }
        )
        .alert(
            isPresented: self.$showAlert,
            content: {
                self.notificationReminder()
            }
        )
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
        .navigationTitle("Notiser")
        .navigationBarTitleDisplayMode(.automatic)
    }
}

extension NotificationsView {
    func notificationReminder() -> Alert {
        Alert(
            title: Text("\u{2757} Notiser krävs"),
            message: Text(
                "Tillåt notiser genom att trycka på \"Öppna iOS-inställningar\" > \"Notiser\" och aktivera \"Tillåt notiser\" samt visning i \"Notiscenter\" och som \"Banderoller\"."
            ),
            dismissButton: .default(Text("OK"))
        )
    }

    @ViewBuilder private func onOff(_ val: Bool) -> some View {
        if val {
            Text(
                NSLocalizedString(
                    "På",
                    comment: "Notification Setting Status is On"
                )
            )
        } else {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.critical)

                Text(
                    NSLocalizedString(
                        "Av",
                        comment: "Notification Setting Status is Off"
                    )
                )
            }
        }
    }

    private var manageNotifications: some View {
        Button(
            action: {
                UIApplication.shared.open(
                    URL(string: UIApplication.openSettingsURLString)!
                )
            }
        ) {
            HStack {
                Text(
                    NSLocalizedString(
                        "Öppna iOS-inställningar",
                        comment: "Manage Permissions in Settings button text"
                    )
                )

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
                    .font(.footnote)
            }
        }
        .accentColor(.primary)
    }

    private var notificationsEnabledStatus: some View {
        HStack {
            Text(
                NSLocalizedString(
                    "Notiser",
                    comment: "Notifications Status text"
                )
            )

            Spacer()

            onOff(!notificationsDisabled)
        }
    }
}
