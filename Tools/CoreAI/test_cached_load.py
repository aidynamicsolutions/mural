#!/usr/bin/env python3
"""Exercise the actual loader's cache-hit-only guard without device inference."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'App/MuralApp.swift').read_text()
loader = source.split('    private static func loadAsset', 1)[1].split('    private static func validate', 1)[0]
swift = '''import Foundation
import OSLog
struct ProbeError: Error { init(_ message: String) {} }
struct SpecializationOptions { static let `default` = Self() }
struct InferenceFunction {}
struct AssetTiming {
    let path: String
    let cacheHit: Bool
    let cacheLookupSeconds, specializationSeconds, functionLoadSeconds: Double
}
enum Policy { case persistent }
final class AIModel {
    static var specializations = 0
    static var loads = 0
    static var failLoad = false
    static func specialize(contentsOf: URL, options: SpecializationOptions, cachePolicy: Policy) async throws -> AIModel {
        specializations += 1
        return AIModel()
    }
    func loadFunction(named: String) throws -> InferenceFunction? {
        AIModel.loads += 1
        if AIModel.failLoad { throw ProbeError("load failure") }
        return InferenceFunction()
    }
}
final class AIModelCache {
    static let `default` = AIModelCache()
    var cached: AIModel?
    func model(for: URL, options: SpecializationOptions) throws -> AIModel? { cached }
}
struct Loader {
    static func loadAsset''' + loader + '''}
@main struct Check {
    static func main() async throws {
        let url = URL(fileURLWithPath: "/verified.encoder.aimodelc")
        do {
            _ = try await Loader.loadAsset(url, requireCached: true)
            fatalError("cache miss was admitted")
        } catch {}
        precondition(AIModel.specializations == 0 && AIModel.loads == 0)
        AIModelCache.default.cached = AIModel()
        let loaded = try await Loader.loadAsset(url, requireCached: true)
        precondition(loaded.timing.cacheHit && AIModel.specializations == 0 && AIModel.loads == 1)
        AIModel.failLoad = true
        do {
            _ = try await Loader.loadAsset(url, requireCached: true)
            fatalError("load error was hidden")
        } catch {}
        precondition(AIModel.specializations == 0 && AIModel.loads == 2)
        AIModel.failLoad = false
        AIModelCache.default.cached = nil
        _ = try await Loader.loadAsset(url)
        precondition(AIModel.specializations == 1 && AIModel.loads == 3)
        print("PASS: cache-only miss does no work; hit loads once; throw never retries; ordinary miss specializes once")
    }
}
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(swift)
    binary = Path(directory) / 'check'
    subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(path), '-o', str(binary)], check=True, timeout=60)
    subprocess.run([str(binary)], check=True, timeout=10)
