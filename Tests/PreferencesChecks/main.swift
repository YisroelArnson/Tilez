import Foundation
import TilezCore

// No persistent domains or real user preferences are changed by these checks.
final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { values[key] }
    override func string(forKey key: String) -> String? { values[key] as? String }
    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    override func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

let storage = MemoryDefaults(suiteName: nil)!
let original = WindowSetup(name: "Existing setup", bundleID: "com.example.app", appName: "Example", count: 6, desktop: "new")
storage.values["setups"] = try JSONEncoder().encode([original])
storage.values["desiredWindows"] = 8
storage.values["gap"] = 5.0
let preferences = Preferences(defaults: storage)
var draft = preferences.arrangementDraft()
assert(draft.count == 8 && draft.gap == 5 && draft.desktop == "current")
draft.count = 12; draft.columns = 4; draft.rows = 3; draft.gap = 14
draft.desktop = "new"; draft.displayID = "test-display"
draft.freshWindows = true; draft.preserveFullScreen = true
assert(preferences.desiredWindows == 8 && preferences.gap == 5)
assert(storage.values["columns"] == nil, "Editing a draft must not write defaults")
assert(preferences.setups == [original])
preferences.useAsDefaults(draft)
let restored = Preferences(defaults: storage)
let nextDraft = restored.arrangementDraft()
assert(nextDraft.count == 12 && nextDraft.columns == 4 && nextDraft.rows == 3 && nextDraft.gap == 14)
assert(nextDraft.desktop == "new" && nextDraft.displayID == "test-display")
assert(nextDraft.freshWindows && nextDraft.keepsFullScreen)
assert(restored.setups == [original], "Changing defaults must not change saved setups")
assert(nextDraft.bundleID.isEmpty && nextDraft.name.isEmpty, "Defaults must not silently select an app or overwrite a setup")
print("PASS: draft isolation, explicit default persistence, and preservation of saved setups")
