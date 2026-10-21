// Run on macOS to validate the SAME JS engine family used by the iOS bridge.
// This is not an iPhone ASR/background test.
import Foundation
import JavaScriptCore

let source = try String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8)
guard let context = JSContext() else { fatalError("No JavaScriptCore") }
context.evaluateScript(source)
guard context.exception == nil else { fatalError("JS load: \(context.exception!)") }
let checks: [(String, String)] = [
    ("Chinese", "new ScriptMatcher('今天我们来测试中文语音提词').update('今天我们来测试').position === 7"),
    ("Normalization", "normalizeScript('你好，１２３！ABC') === '你好123abc'"),
    ("Backtrack", "(function(){let m=new ScriptMatcher('今天我们来测试中文语音提词。窗外的阳光照在桌子上。');m.seek(25);return m.update('今天我们来测试中文语音提词').position===13;})()"),
    ("Ambiguity", "(function(){let m=new ScriptMatcher('红色气球慢慢升起。远处有许多观众正在等候。红色气球慢慢升起。');m.seek(16);return m.update('红色气球慢慢升起').reason==='ambiguous';})()")
]
for (name, expression) in checks {
    guard context.evaluateScript(expression)?.toBool() == true, context.exception == nil else { fatalError("Failed: \(name)") }
    print("PASS \(name)")
}
