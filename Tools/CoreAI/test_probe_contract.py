#!/usr/bin/env python3
"""Check the actual probe's finite argmax and artifact identity helpers on macOS."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / "App/MuralApp.swift").read_text()
shared = (Path(__file__).resolve().parents[2] / "App/LocalConversationEngine.swift").read_text()
helpers = shared.split("    static func sha256", 1)[1].split("\n}\n#endif", 1)[0].replace("Failure(", "ProbeError(")
helpers += "\n    private static func checkedArgmax" + source.split("    private static func checkedArgmax", 1)[1].split("\n}\n\n@MainActor", 1)[0]
swift = '''import CryptoKit
import Foundation
struct ProbeError: Error { init(_ message: String) {} }
struct Probe {
    static func sha256''' + helpers.replace("private static func", "static func") + '''
}
func expectFailure(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Accepted invalid input") } catch {}
}
let first = try Probe.checkedArgmax([1, 4, 4], allowed: nil, suppressed: [])
precondition(first == 1)
let allowed = try Probe.checkedArgmax([1, 4, 4], allowed: [0, 2], suppressed: [])
precondition(allowed == 2)
let suppressed = try Probe.checkedArgmax([1, 4, 4], allowed: nil, suppressed: [1])
precondition(suppressed == 2)
for invalid: Float in [.nan, .infinity, -.infinity] {
    expectFailure { _ = try Probe.checkedArgmax([1, invalid], allowed: [0], suppressed: [1]) }
}
expectFailure { _ = try Probe.checkedArgmax([], allowed: nil, suppressed: []) }
expectFailure { _ = try Probe.checkedArgmax([1], allowed: nil, suppressed: [0]) }
expectFailure { _ = try Probe.checkedArgmax([1], allowed: [-1, 2], suppressed: []) }
let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: root) }
let a = root.appending(path: "a"), b = root.appending(path: "b")
try Data([1, 2]).write(to: a)
try Data([3, 4]).write(to: b)
let before = try Probe.fingerprint(root)
try FileManager.default.removeItem(at: a)
try Data([1, 2]).write(to: a)
let reordered = try Probe.fingerprint(root)
precondition(before == reordered)
try Data([2, 1]).write(to: a) // Same name and size must not admit stale input.
let changed = try Probe.fingerprint(root)
precondition(before != changed)
let link = root.appending(path: "link")
try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
expectFailure { _ = try Probe.fingerprint(root) }
print("PASS: finite logits, filtering/ties, content identity, ordering, symlink rejection")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "probe-contract.swift"
    path.write_text(swift)
    subprocess.run(["xcrun", "swift", str(path)], check=True, timeout=120)
