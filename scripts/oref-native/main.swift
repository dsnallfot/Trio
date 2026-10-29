import Foundation
@testable import Trio

func run() throws {
    let request = try JSONSerialization.jsonObject(with: FileHandle.standardInput.readDataToEndOfFile()) as! [String: Any]
    let args = request["arguments"] as! [String]
    func json(_ i: Int) throws -> String {
        args[i]
    }
    let clock = try JSONBridge.clock(from: "\"\(request["clock"] as! String)\"")
    let result: OrefFunctionResult
    switch request["module"] as! String {
    case "profile": result = try OpenAPSSwift.makeProfile(
            preferences: json(4),
            pumpSettings: json(0),
            bgTargets: json(1),
            basalProfile: json(3),
            isf: json(2),
            carbRatio: json(5),
            tempTargets: json(6),
            model: json(7),
            trioSettings: json(9),
            clock: clock
        )
    case "autosens": result = try OpenAPSSwift.autosense(
            glucose: json(0),
            pumpHistory: json(1),
            basalProfile: json(2),
            profile: json(3),
            carbs: json(4),
            tempTargets: json(5),
            clock: clock
        )
    case "meal": result = try OpenAPSSwift.meal(
            pumphistory: json(0),
            profile: json(1),
            basalProfile: json(4),
            clock: json(2),
            carbs: json(5),
            glucose: json(3)
        )
    case "iob": result = try OpenAPSSwift.iob(pumphistory: json(0), profile: json(1), clock: json(2), autosens: json(3))
    default: result = try OpenAPSSwift.determineBasal(
            glucose: json(2),
            currentTemp: json(1),
            iob: json(0),
            profile: json(3),
            autosens: json(4),
            meal: json(5),
            microBolusAllowed: try JSONBridge.from(string: args[6]),
            reservoir: json(7),
            pumpHistory: json(9),
            preferences: json(10),
            basalProfile: json(11),
            trioCustomOrefVariables: json(12),
            clock: clock
        )
    }
    print(try result.returnOrThrow())
}

do { try run() } catch { fputs("\(error)\n", stderr)
    exit(1) }
