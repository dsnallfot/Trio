//
//  GlucoseNotificationOption.swift
//  FreeAPS
//
//  Created by Kimberlie Skandis on 1/18/25.
//
import Foundation

public enum GlucoseNotificationsOption: String, JSON, CaseIterable, Identifiable, Codable, Hashable {
    public var id: String { rawValue }
    case disabled
    case alwaysEveryCGM
    case onlyAlarmLimits

    var displayName: String {
        switch self {
        case .disabled: return "Avaktiverade"
        case .alwaysEveryCGM: return "Alltid"
        case .onlyAlarmLimits: return "Endast vid alarmgränser"
        }
    }
}
