#!/usr/bin/env python3
"""Compile the real Talk backend gate for default, Debug, and opted-in Release."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'App/LocalConversationEngine.swift').read_text()
gate = source.split('    static var enabled: Bool {', 1)[1].split('\n    @concurrent static func verifiedURL', 1)[0]
swift = 'import Foundation\nenum Gate {\n    static var enabled: Bool {' + gate + '\n}\nprint(Gate.enabled)\n'
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(swift)
    for name, flags, without_flag, with_flag in [
        ('release', [], 'false', 'false'),
        ('debug', ['-D', 'DEBUG'], 'false', 'true'),
        ('opt-in-release', ['-D', 'MURAL_COREAI_TALK'], 'true', 'true'),
    ]:
        binary = Path(directory) / name
        subprocess.run(['xcrun', 'swiftc', *flags, str(path), '-o', str(binary)], check=True, timeout=60)
        for args, expected in [([], without_flag), (['--coreai-talk-gpu'], with_flag)]:
            result = subprocess.run([str(binary), *args], check=True, capture_output=True, text=True, timeout=10)
            assert result.stdout.strip() == expected, (name, args, result.stdout)
print('PASS: normal Release ignores opt-in launch flag; Debug defaults off; explicit build opt-in is required for Release')
