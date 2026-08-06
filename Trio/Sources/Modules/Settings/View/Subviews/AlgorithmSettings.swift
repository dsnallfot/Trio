//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct AlgorithmSettings: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Oref algoritm inställningar"),
                content: {
                    Text("Autosens").navigationLink(to: .autosensSettings, from: self)
                    Text("Super mikrobolus (SMB)").navigationLink(to: .smbSettings, from: self)
                    Text("Dynamisk dosering").navigationLink(to: .dynamicISF, from: self)
                    Text("Målbeteende").navigationLink(to: .targetBehavior, from: self)
                    Text("Extra").navigationLink(to: .algorithmAdvancedSettings, from: self)
                }
            ).listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Algoritm")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
