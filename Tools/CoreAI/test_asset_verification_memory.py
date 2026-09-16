#!/usr/bin/env python3
"""Run Talk's actual hashing loop; large input must not accumulate read buffers."""
from pathlib import Path
import hashlib
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'App/LocalConversationEngine.swift').read_text()
loop = source.split('                // Foundation read buffers must drain per chunk,', 1)[1]
loop = loop[loop.index('                while try autoreleasepool'):].split('}) {}', 1)[0] + '}) {}'
size = 256 * 1024 * 1024
expected = hashlib.sha256()
for _ in range(256):
    expected.update(bytes(1024 * 1024))
swift = '''import CryptoKit
import Darwin
import Foundation
@main struct Check {
    static func main() async throws {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: CommandLine.arguments[1]))
        defer { try? handle.close() }
        var hash = SHA256(), bytes = 0
''' + loop + '''
        precondition(bytes == 256 * 1024 * 1024)
        precondition(hash.finalize().map { String(format: "%02x", $0) }.joined() == "''' + expected.hexdigest() + '''")
        var usage = rusage()
        precondition(getrusage(RUSAGE_SELF, &usage) == 0)
        print("peak RSS bytes: \\(usage.ru_maxrss)")
        precondition(usage.ru_maxrss < 128 * 1024 * 1024, "File read buffers accumulated")
        print("PASS: exact 256 MiB hash with bounded temporary buffers")
    }
}
'''
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    data = root / 'zeros'
    with data.open('wb') as output:
        output.truncate(size)
    path = root / 'check.swift'
    path.write_text(swift)
    binary = root / 'check'
    subprocess.run(['xcrun', 'swiftc', '-O', '-parse-as-library', str(path), '-o', str(binary)], check=True, timeout=60)
    subprocess.run([str(binary), str(data)], check=True, timeout=30)
