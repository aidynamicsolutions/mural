#!/usr/bin/env python3
"""Run the app's actual hybrid tensor bridge on macOS, without Core AI runtime."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / "App/MuralApp.swift").read_text()
shared = (Path(__file__).resolve().parents[2] / "App/LocalConversationEngine.swift").read_text()
helpers = shared.split("    static func decoderEmbeddings", 1)[1].split(
    "    static func sha256", 1
)[0].replace("Failure(", "ProbeError(")
arguments = source.split("    private static func whisperKitProofUsesFreshEncoder", 1)[1].split(
    "    // Deliberately only fixture 001", 1
)[0]
swift = '''import CoreML
import Foundation
struct ProbeError: Error { init(_ message: String) {} }
struct Bridge {
    static func decoderEmbeddings''' + helpers.replace("private static func", "static func") + '''
    static func whisperKitProofUsesFreshEncoder''' + arguments + '''}
func fails(_ operation: () throws -> Void) {
    do { try operation(); fatalError("Accepted invalid tensor") } catch is ProbeError {} catch { fatalError("Unexpected error: \\(error)") }
}
let base = ["--coreai-whisperkit=baseline", "--coreai-fixture=001.wav"]
let hybrid = ["--coreai-whisperkit=hybrid", "--coreai-fixture=001.wav"]
let fresh = "--coreai-hybrid-fresh-encoder"
let invalidate = "--coreai-hybrid-invalidate-encoder"
let release = "--coreai-hybrid-release-after-first"
let recreate = "--coreai-hybrid-recreate-between-turns"
let invalidationFresh = try Bridge.whisperKitProofUsesFreshEncoder(hybrid + [fresh, invalidate], mode: "hybrid")
precondition(invalidationFresh)
let baselineFresh = try Bridge.whisperKitProofUsesFreshEncoder(base, mode: "baseline")
let hybridFresh = try Bridge.whisperKitProofUsesFreshEncoder(hybrid + [fresh], mode: "hybrid")
let hybridRelease = try Bridge.whisperKitProofUsesFreshEncoder(hybrid + [release], mode: "hybrid")
let hybridRecreate = try Bridge.whisperKitProofUsesFreshEncoder(hybrid + [recreate], mode: "hybrid")
precondition(!baselineFresh && hybridFresh && !hybridRelease && !hybridRecreate)
fails { _ = try Bridge.whisperKitProofUsesFreshEncoder(base + [fresh], mode: "baseline") }
for args in [base + [fresh], base + [release], base + [recreate], hybrid + [fresh, fresh], hybrid + [fresh + "=yes"],
             hybrid + [invalidate], hybrid + [fresh, invalidate, invalidate], hybrid + [fresh, invalidate + "=yes"],
             hybrid + [release, release], hybrid + [release + "=yes"], hybrid + [fresh, release],
             hybrid + [invalidate, release], hybrid + [recreate, recreate], hybrid + [recreate + "=yes"],
             hybrid + [fresh, recreate], hybrid + [invalidate, recreate], hybrid + [release, recreate],
             hybrid + ["--coreai-decode-only"],
             hybrid + ["--coreai-encoder-path=/tmp/model"],
             hybrid + ["--coreai-stateful=steps"], hybrid + ["--coreai-fixture=002.wav"],
             ["--coreai-whisperkit=hybrid"]] {
    fails { _ = try Bridge.whisperKitProofUsesFreshEncoder(args, mode: "hybrid") }
}
let values = (0..<(1500 * 1280)).map { i in Float16(bitPattern: UInt16(i % 0x7c00)) }
let output = try Bridge.decoderEmbeddings(values)
let p = output.dataPointer.assumingMemoryBound(to: Float16.self)
let s = output.strides.map(\\.intValue)
for t in 0..<1500 { for c in 0..<1280 {
    precondition(p[c * s[1] + t * s[3]].bitPattern == values[t * 1280 + c].bitPattern)
}}
let roundtrip = try Bridge.readDecoderEmbeddings(output)
precondition(roundtrip.map(\\.bitPattern) == values.map(\\.bitPattern))
// Independently exercise the reader with non-contiguous time and channel strides.
let count = 1280 * 3001
let memory = UnsafeMutableRawPointer.allocate(byteCount: count * 2, alignment: 16)
defer { memory.deallocate() }
let strided = try MLMultiArray(dataPointer: memory, shape: [1,1280,1,1500], dataType: .float16,
    strides: [NSNumber(value: count),3001,3000,2], deallocator: nil)
let q = memory.assumingMemoryBound(to: Float16.self)
for c in 0..<1280 { for t in 0..<1500 { q[c * 3001 + t * 2] = values[t * 1280 + c] } }
let read = try Bridge.readDecoderEmbeddings(strided)
precondition(read.map(\\.bitPattern) == values.map(\\.bitPattern))
for invalid: Float16 in [.nan, .infinity, -.infinity] {
    q[0] = invalid
    fails { _ = try Bridge.readDecoderEmbeddings(strided) }
    var bad = values; bad[0] = invalid
    fails { _ = try Bridge.decoderEmbeddings(bad) }
}
fails { _ = try Bridge.decoderEmbeddings([]) }
for (shape, dtype) in [([1,1500,1280], MLMultiArrayDataType.float16), ([1,1280,1,1500], .float32)] {
    let bad = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: dtype)
    fails { _ = try Bridge.readDecoderEmbeddings(bad) }
}
print("PASS: hybrid argument guards, layout, bit preservation, strided reads, invalid shape/type/finite guards")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "hybrid-layout.swift"
    path.write_text(swift)
    subprocess.run(["xcrun", "swift", str(path)], check=True, timeout=120)
