#!/usr/bin/env python3
"""Compile the actual portable Swift verifier; Core AI extension not tested here."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

from w8_identity import identity

root = Path(__file__).resolve().parent
if not shutil.which("swiftc"):
    raise SystemExit("BLOCKED: Swift compiler not found (no pass claimed)")
spec = identity({"kind": "tiny", "format": "fp8"})
with tempfile.TemporaryDirectory() as temporary:
    tmp = Path(temporary)
    (tmp / "spec.json").write_text(json.dumps(spec))
    (tmp / "main.swift").write_text(r'''
import Foundation
let spec = try JSONDecoder().decode(W8IdentitySpec.self,
    from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
try spec.requireFunctions([spec.entrypoint])
try spec.requireMarker(spec.markerValues)
func rejects(_ action: () throws -> Void) {
    do { try action(); fatalError("Invalid identity accepted") } catch {}
}
rejects { try spec.requireFunctions(["main"]) }
rejects { try spec.requireFunctions([spec.entrypoint, "main"]) }
rejects { try spec.requireMarker(Array(spec.markerValues.dropLast())) }
rejects { try spec.requireMarker([Int32](repeating: 0, count: spec.markerValues.count)) }
print("PASS: portable Swift identity guard; native Core AI not exercised")
''')
    subprocess.run(["swiftc", "-D", "MURAL_W8_IDENTITY_PORTABLE_TEST", str(root / "W8IdentityVerifier.swift"), str(tmp / "main.swift"),
                    "-o", str(tmp / "check")], check=True)
    subprocess.run([str(tmp / "check"), str(tmp / "spec.json")], check=True)
