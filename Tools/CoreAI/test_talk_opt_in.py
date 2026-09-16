#!/usr/bin/env python3
"""Compile the real Talk backend gate and diagnostic for each build configuration."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'App/LocalConversationEngine.swift').read_text()
gate = source.split('    static var enabled: Bool {', 1)[1].split('\n    @concurrent static func verifiedURL', 1)[0]
backend = source.split('    nonisolated static var conversationASRBackend: String {', 1)[1].split('\n    override init()', 1)[0]
swift = ('import Foundation\nenum PhoWhisperStagedEncoder {\n    static var enabled: Bool {' + gate +
         '\n}\nenum LocalConversationEngine {\n    nonisolated static var conversationASRBackend: String {' + backend +
         '\n}\nprint(PhoWhisperStagedEncoder.enabled)\nprint(LocalConversationEngine.conversationASRBackend)\n'
         '#if canImport(CoreAI)\nprint(true)\n#else\nprint(false)\n#endif\n')
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
            enabled, description, coreai_available = result.stdout.strip().splitlines()
            assert enabled == expected, (name, args, result.stdout)
            expected_description = ('Core AI GPU-preferred encoder + Core ML decoder (staged)'
                                    if expected == 'true' and coreai_available == 'true'
                                    else 'WhisperKit / Core ML (eager)')
            assert description == expected_description, (name, args, result.stdout)
print('PASS: six backend gate/diagnostic cases; Release requires build opt-in, not a launch flag')
