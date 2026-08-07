//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct TherapySettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Allmänna inställningar"),
                content: {
                    Text("Enheter & gränsvärden").navigationLink(to: .unitsAndLimits, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Insulin och målinställningar"),
                content: {
                    Text("Basalprofil").navigationLink(to: .basalProfileEditor, from: self)
                    Text("Insulinkänslighet").navigationLink(to: .isfEditor, from: self)
                    Text("Insulinkvoter").navigationLink(to: .crEditor, from: self)
                    Text("Målglukos").navigationLink(to: .targetsEditor, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Behandling")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
