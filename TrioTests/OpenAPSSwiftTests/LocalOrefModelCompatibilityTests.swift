import Foundation
import Testing
@testable import Trio

@Suite("Local model contracts retained during Swift Oref import") struct LocalOrefModelCompatibilityTests {
    @Test("Mutable dosing fields preserve local bolus and insulin JSON") func determinationRoundTrip() throws {
        let input =
            #"{"reason":"synthetic","units":0.1,"insulinReq":0.2,"rate":0.9,"duration":30,"TDD":24.4,"insulin":{"TDD":24.4,"bolus":0.5,"temp_basal":23.4,"scheduled_basal":0.5},"insulinForManualBolus":0.71,"manualBolusErrorString":2,"received":false}"#
        var value = try JSONCoding.decoder.decode(Determination.self, from: Data(input.utf8))
        let encoded = try JSONCoding.encoder.encode(value)
        let before = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: encoded) as! NSDictionary
        #expect(before == after)

        value.units = Decimal(string: "0.2")
        value.insulinReq = Decimal(string: "0.3")
        value.rate = Decimal(string: "0.8")
        value.duration = 60
        value.tdd = 25
        let changed = try JSONCoding.decoder.decode(Determination.self, from: JSONCoding.encoder.encode(value))
        #expect(changed.units == Decimal(string: "0.2"))
        #expect(changed.insulinReq == Decimal(string: "0.3"))
        #expect(changed.rate == Decimal(string: "0.8"))
        #expect(changed.duration == 60)
        #expect(changed.tdd == 25)
        #expect(changed.insulin == value.insulin)
        #expect(changed.insulinForManualBolus == Decimal(string: "0.71"))
        #expect(changed.manualBolusErrorString == 2)
    }

    @Test("Swift autosens diagnostics do not change legacy JS autosens storage") func autosensContractsRemainSeparate() throws {
        let input = Data(#"{"ratio":1,"error":"not enough glucose data to calculate autosens"}"#.utf8)
        let legacy = try JSONCoding.decoder.decode(Autosens.self, from: input)
        let native = try JSONCoding.decoder.decode(SwiftOrefAutosens.self, from: input)
        #expect(legacy.ratio == native.ratio)
        #expect(native.error == "not enough glucose data to calculate autosens")
        let encoded = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(legacy)) as! NSDictionary
        #expect(encoded == ["ratio": 1] as NSDictionary)
    }

    @Test("Early-return optional result fields stay absent rather than becoming zero") func earlyReturnEncoding() throws {
        let input = #"{"reason":"synthetic early return","rate":0,"duration":0}"#
        let value = try JSONCoding.decoder.decode(Determination.self, from: Data(input.utf8))
        let encoded = try JSONSerialization.jsonObject(with: JSONCoding.encoder.encode(value)) as! NSDictionary
        let original = try JSONSerialization.jsonObject(with: Data(input.utf8)) as! NSDictionary
        #expect(encoded == original)
        #expect(value.insulinForManualBolus == nil)
        #expect(value.insulin == nil)
        #expect(value.tdd == nil)
    }
}
