import Foundation
import JavaScriptCore

// Standalone test process: no app storage, networking, or pump interfaces.
// One context per invocation, matching JavaScriptWorker.inCommonContext.
func run() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let requestData = FileHandle.standardInput.readDataToEndOfFile()
    let request = try JSONSerialization.jsonObject(with: requestData) as! [String: Any]
    let module = request["module"] as! String
    let scripts: [String: [String]] = [
        "profile": ["bundle/profile", "prepare/profile"],
        "iob": ["bundle/iob", "prepare/iob"],
        "meal": ["bundle/meal", "prepare/meal"],
        "autosens": ["bundle/autosens", "prepare/autosens"],
        "determineBasal": [
            "prepare/determine-basal",
            "bundle/basal-set-temp",
            "bundle/glucose-get-last",
            "bundle/determine-basal"
        ]
    ]
    guard let paths = scripts[module], let context = JSContext() else {
        throw NSError(domain: "Replay", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unknown module or unavailable JSContext"])
    }
    var failure: String?
    context.exceptionHandler = { _, error in failure = error?.toString() ?? "Unknown JS error" }
    func evaluate(_ source: String) throws -> JSValue {
        failure = nil
        let result = context.evaluateScript(source)
        if let failure { throw NSError(domain: "JavaScript", code: 1, userInfo: [NSLocalizedDescriptionKey: failure]) }
        guard let result else { throw NSError(domain: "Replay", code: 2) }
        return result
    }
    context.setObject(request["clock"], forKeyedSubscript: "replayClock" as NSString)
    _ = try evaluate("""
    var _consoleLog = function() {};
    var NativeDate = Date;
    var frozenTime = NativeDate.parse(replayClock);
    if (!Number.isFinite(frozenTime)) throw new Error('Invalid replay clock');
    function FrozenDate(...args) {
        if (!new.target) return new NativeDate(frozenTime).toString();
        return Reflect.construct(NativeDate, args.length ? args : [frozenTime], new.target);
    }
    Object.setPrototypeOf(FrozenDate, NativeDate);
    FrozenDate.prototype = NativeDate.prototype;
    FrozenDate.now = function() { return frozenTime; };
    Date = FrozenDate;
    if (Date.now() !== frozenTime || +new Date() !== frozenTime ||
        Date() !== new NativeDate(frozenTime).toString() ||
        +new Date(0) !== 0 || !Number.isNaN(+new Date(undefined)) ||
        Date.parse(replayClock) !== frozenTime ||
        Date.UTC(2000, 0, 1) !== NativeDate.UTC(2000, 0, 1) ||
        !(new Date() instanceof Date) ||
        +new Date(2020, 1, 2, 3, 4, 5, 6) !== +new NativeDate(2020, 1, 2, 3, 4, 5, 6))
        throw new Error('Frozen Date contract failed');
    """)
    let offset = try evaluate("new Date().getTimezoneOffset()").toInt32()
    guard offset == (request["timezoneOffsetMinutes"] as! NSNumber).int32Value else {
        throw NSError(domain: "Replay", code: 3, userInfo: [NSLocalizedDescriptionKey: "JS timezone mismatch: \(offset)"])
    }
    for path in ["prepare/log"] + paths {
        context.setObject(path + ".js", forKeyedSubscript: "scriptName" as NSString)
        let url = root.appendingPathComponent("Trio/Resources/javascript/\(path).js")
        _ = try evaluate(String(contentsOf: url, encoding: .utf8))
    }
    // Serialize/reparse inputs to reproduce the production JSON argument boundary.
    let args = try JSONSerialization.data(withJSONObject: request["arguments"]!)
    context.setObject(String(data: args, encoding: .utf8)!, forKeyedSubscript: "replayArgumentsJSON" as NSString)
    let output = try evaluate("JSON.stringify(generate.apply(null, JSON.parse(replayArgumentsJSON)))")
    guard !output.isUndefined, let json = output.toString() else {
        throw NSError(domain: "Replay", code: 4, userInfo: [NSLocalizedDescriptionKey: "Undefined algorithm output"])
    }
    print(json)
}

do { try run() } catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
