#!/usr/bin/env python3
"""Compile production models and payload encoding blocks without network traffic."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
api = (root / 'Trio/Sources/Services/Network/Nightscout/NightscoutAPI.swift').read_text()
models = '\n'.join((root / f'Trio/Sources/Models/{name}.swift').read_text()
                   for name in ['NightscoutTreatment', 'NightscoutExercise'])


def encoding_block(method, start, end):
    offset = api.index(f'    func {method}(')
    first = api.index(start, offset)
    return api[first:api.index(end, first)]


stubs = r'''
import Foundation
protocol JSON: Codable {}
extension JSON {
    init?(from: String) {
        guard let value = try? JSONCoding.decoder.decode(Self.self, from: Data(from.utf8)) else { return nil }
        self = value
    }
}
struct PumpHistoryEvent: Codable {}
enum PumpEventStored { enum EventType: String, Codable { case note = "Note" } }
enum OverrideStored { enum EventType: String, Codable { case exercise = "Exercise" } }
enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
'''
functions = ''
for method, argument, kind in [('uploadTreatments', 'treatments', 'NightscoutTreatment'),
                               ('uploadOverrides', 'overrides', 'NightscoutExercise')]:
    block = encoding_block(method, '            let sentAt = Date()', '            request.httpBody')
    functions += f'func {method}(_ {argument}: [{kind}]) throws -> Data {{\n{block}\nreturn encodedBody\n}}\n'
block = encoding_block('uploadErrors', '        var payload = errorNote', '        request.httpMethod')
block = block.replace('request.httpBody =', 'return')
functions += f'func uploadErrors(_ errorNote: NightscoutTreatment) throws -> Data {{\n{block}\n}}\n'
check = encoding_block('checkConnection', '        struct Check:', '        let check = Check()')
functions += f'func connectionNote() throws -> Data {{\n{check}\nreturn try JSONCoding.encoder.encode(Check())\n}}\n'
tests = r'''
func object(_ data: Data) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: data) as! [String: Any]
}
func batch(_ data: Data) throws -> [[String: Any]] {
    try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
}
func checkTimestamp(_ value: [String: Any]) {
    let date = ISO8601DateFormatter().date(from: value["trioSentAt"] as! String)!
    precondition(abs(date.timeIntervalSinceNow) < 5)
}
var treatment = NightscoutTreatment(from: #"{"eventType":"Note","created_at":"2020-01-01T00:00:00Z","notes":"test"}"#)!
precondition(treatment.trioSentAt == nil)
let unstamped = try object(JSONCoding.encoder.encode(treatment))
precondition(unstamped["trioSentAt"] == nil)
treatment.trioSentAt = Date(timeIntervalSince1970: 1)
let sent = try batch(uploadTreatments([treatment, treatment]))
precondition(sent.count == 2 && sent[0]["trioSentAt"] as! String == sent[1]["trioSentAt"] as! String)
for value in sent {
    checkTimestamp(value)
    precondition(value["created_at"] as! String == "2020-01-01T00:00:00Z")
    precondition(value["notes"] as! String == "test")
}
precondition(treatment.trioSentAt == Date(timeIntervalSince1970: 1))
let decoded = try JSONCoding.decoder.decode([NightscoutTreatment].self, from: uploadTreatments([treatment]))
precondition(decoded[0].trioSentAt != nil && decoded[0] == treatment)
checkTimestamp(try object(uploadErrors(treatment)))
let exercise = NightscoutExercise(from: #"{"eventType":"Exercise","created_at":"2020-01-01T00:00:00Z"}"#)!
precondition(exercise.trioSentAt == nil)
checkTimestamp(try batch(uploadOverrides([exercise]))[0])
checkTimestamp(try object(connectionNote()))
print("PASS: optional timestamp decoding, all treatment payloads, batch timestamps, preserved event dates and source values")
'''
with tempfile.TemporaryDirectory(prefix='trio-sent-at-') as directory:
    path = Path(directory)
    swift = path / 'main.swift'
    swift.write_text(stubs + models + functions + tests)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(path / 'cache'),
                    str(swift), '-o', str(path / 'tests')], check=True)
    subprocess.run([str(path / 'tests')], check=True)
