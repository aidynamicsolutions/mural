#!/usr/bin/env python3
"""Run the app's actual mel reader against Core ML arrays: python3 Tools/CoreAI/test_mel_reader.py."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / "App/MuralApp.swift").read_text()
reader = source.split("    private static func readAcceptedMel", 1)[1].split(
    "    private static func fillFloat", 1
)[0]
swift = '''import CoreML
import Foundation
struct ProbeError: Error { init(_ message: String) {} }
struct Reader {
    static func readAcceptedMel''' + reader + '''}
for dtype in [MLMultiArrayDataType.float16, .float32] {
    for shape in [[1, 80, 3000], [1, 80, 1, 3000]] {
        // Non-contiguous rows and columns exercise the real stride handling.
        let strides = shape.count == 3 ? [480080, 6001, 2] : [480080, 6001, 6000, 2]
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: 480080 * 4, alignment: 16)
        defer { bytes.deallocate() }
        let array = try MLMultiArray(dataPointer: bytes, shape: shape.map(NSNumber.init),
            dataType: dtype, strides: strides.map(NSNumber.init), deallocator: nil)
        let values: [Float16] = [0, -0.5, 1.25, .leastNonzeroMagnitude, .greatestFiniteMagnitude]
        for m in 0..<80 { for t in 0..<3000 {
            let offset = m * 6001 + t * 2
            let value = values[(m + t) % values.count]
            if dtype == .float16 { bytes.storeBytes(of: value, toByteOffset: offset * 2, as: Float16.self) }
            else { bytes.storeBytes(of: Float(value), toByteOffset: offset * 4, as: Float.self) }
        }}
        let actual = try Reader.readAcceptedMel(array)
        for m in 0..<80 { for t in 0..<3000 {
            precondition(actual[m * 3000 + t] == Float(values[(m + t) % values.count]))
        }}
        if dtype == .float16 { bytes.storeBytes(of: Float16.nan, as: Float16.self) }
        else { bytes.storeBytes(of: Float.infinity, as: Float.self) }
        do { _ = try Reader.readAcceptedMel(array); fatalError("Accepted non-finite mel") }
        catch is ProbeError {}
    }
}
for (shape, dtype) in [([1, 80, 3000], MLMultiArrayDataType.int32), ([1, 128, 3000], .float32)] {
    let array = try MLMultiArray(shape: shape.map(NSNumber.init), dataType: dtype)
    do { _ = try Reader.readAcceptedMel(array); fatalError("Accepted invalid contract") }
    catch is ProbeError {}
}
print("PASS: FP16/FP32 values, both shapes, non-contiguous strides, non-finite/type/shape rejection")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "mel-reader.swift"
    path.write_text(swift)
    subprocess.run(["xcrun", "swift", str(path)], check=True, timeout=120)
