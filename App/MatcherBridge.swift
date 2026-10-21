import Foundation
import JavaScriptCore

final class MatcherBridge {
    private let context: JSContext
    private let matcher: JSValue
    let characters: [String]

    init(script: String) throws {
        guard let context = JSContext(),
              let url = Bundle.main.url(forResource: "matcher", withExtension: "js") else {
            throw NSError(domain: "Matcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "缺少匹配脚本"])
        }
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        guard context.exception == nil,
              let constructor = context.objectForKeyedSubscript("ScriptMatcher"),
              let matcher = constructor.construct(withArguments: [script]),
              !matcher.isUndefined,
              let normalizer = context.objectForKeyedSubscript("normalizeScript"),
              let normalized = normalizer.call(withArguments: [script])?.toString() else {
            throw NSError(domain: "Matcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "匹配脚本初始化失败"])
        }
        self.context = context
        self.matcher = matcher
        characters = normalized.map(String.init)
    }

    func update(_ transcript: String) -> (position: Int, reason: String, confidence: Double)? {
        context.exception = nil
        guard let value = matcher.invokeMethod("update", withArguments: [transcript]),
              context.exception == nil, let object = value.toDictionary(),
              let position = object["position"] as? NSNumber,
              let reason = object["reason"] as? String,
              let confidence = object["confidence"] as? NSNumber else { return nil }
        return (position.intValue, reason, confidence.doubleValue)
    }
    func newUtterance() { matcher.invokeMethod("newUtterance", withArguments: []) }
    func seek(_ position: Int) { matcher.invokeMethod("seek", withArguments: [position]) }
}
