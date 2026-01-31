//
//  FeatureSettingsView.swift
//  Trio
//
//  Created by Deniz Cengiz on 26.07.24.
//
import Foundation
import SwiftUI
import Swinject

struct FeatureSettingsView: BaseView {
    let resolver: Resolver

    @ObservedObject var state: Settings.StateModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(AppState.self) var appState

    var body: some View {
        Form {
            Section(
                header: Text("Trio funktioner"),
                content: {
                    Text("Boluskalkylator").navigationLink(to: .bolusCalculatorConfig, from: self)
                    Text("Måltidsinställningar").navigationLink(to: .mealSettings, from: self)
                    Text("Genvägar").navigationLink(to: .shortcutsConfig, from: self)
                    Text("Fjärrstyrning").navigationLink(to: .remoteControlConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)

            Section(
                header: Text("Trio personalisering"),
                content: {
                    Text("Användargränssnitt").navigationLink(to: .userInterfaceSettings, from: self)
                    Text("Appikoner").navigationLink(to: .iconConfig, from: self)
                }
            )
            .listRowBackground(Color.chart)
        }
        .scrollContentBackground(.hidden)
        .background(appState.trioBackgroundColor(for: colorScheme))
        .navigationTitle("Funktioner")
        .navigationBarTitleDisplayMode(.automatic)
    }
}
