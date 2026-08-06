//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct DevicesView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Ställ in och konfigurera"),
                content: {
                    Text("Insulinpump").navigationLink(to: .pumpConfig, from: self)
                    Text("CGM (Kontinuerlig glukosmätare)").navigationLink(to: .cgm, from: self)
                    Text("Smartwatch").navigationLink(to: .watch, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Hårdvara")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
