import Foundation
import Testing
@testable import MuralCore

struct CoreMLPreparationReceiptTests {
    private func key(model: String = "test-model", scope: CoreMLPreparationReceipt.Scope = .eager,
                     manifest: String = "manifest-a", path: String = "path-a", os: String = "build-a",
                     device: String = "device-a", compute: [String: Int] = ["decoder": 3],
                     policy: Int = 1) -> CoreMLPreparationReceipt.Key {
        .init(model: model, scope: scope, manifestSHA256: manifest, modelPathSHA256: path,
              osBuild: os, device: device, computeUnits: compute, policyVersion: policy)
    }
    private func file() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("receipt.json")
    }
    private func clean(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    private enum Failure: Error { case expected }

    @Test func successfulMissThenFreshOwnerHit() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        var prewarms = 0, loads = 0
        #expect(receipt.lookup() == .missing)
        let first = try await receipt.prepare(prewarm: { prewarms += 1 }, loadAndValidate: { loads += 1 })
        #expect(first.didPrewarm && first.receiptWritten)
        let data = try Data(contentsOf: file)
        let nextOwner = CoreMLPreparationReceipt(key: key(), file: file)
        let second = try await nextOwner.prepare(prewarm: { prewarms += 1 }, loadAndValidate: { loads += 1 })
        #expect(!second.didPrewarm && !second.receiptWritten)
        #expect(prewarms == 1 && loads == 2)
        #expect(try Data(contentsOf: file) == data) // A hit does not rewrite an old success.
    }

    @Test func everySpecializationInputInvalidates() async throws {
        let file = file(); defer { clean(file) }
        _ = try await CoreMLPreparationReceipt(key: key(), file: file).prepare(prewarm: {}, loadAndValidate: {})
        let changed = [key(model: "other"), key(scope: .stagedDecoder), key(manifest: "manifest-b"),
                       key(path: "path-b"), key(os: "build-b"), key(device: "device-b"),
                       key(compute: ["decoder": 0]), key(policy: 2)]
        for key in changed {
            #expect(CoreMLPreparationReceipt(key: key, file: file).lookup() == .incompatible)
        }
    }

    @Test func corruptReceiptIsAMiss() async throws {
        let file = file(); defer { clean(file) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: file)
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        #expect(receipt.lookup() == .unreadable)
        let result = try await receipt.prepare(prewarm: {}, loadAndValidate: {})
        #expect(result.didPrewarm && result.receiptWritten)
        #expect(receipt.lookup() == .hit)
    }

    @Test func failedPrewarmDoesNotLoadOrRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        var loaded = false
        await #expect(throws: Failure.self) {
            _ = try await receipt.prepare(prewarm: { throw Failure.expected }, loadAndValidate: { loaded = true })
        }
        #expect(!loaded && receipt.lookup() == .missing)
    }

    @Test func failedLoadOrContractDoesNotRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        await #expect(throws: Failure.self) {
            _ = try await receipt.prepare(prewarm: {}, loadAndValidate: { throw Failure.expected })
        }
        #expect(receipt.lookup() == .missing)
    }

    @Test func cancellationBeforePrewarmDoesNotRunOrRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await receipt.prepare(prewarm: { Issue.record("Unexpected prewarm") },
                                             loadAndValidate: { Issue.record("Unexpected load") })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(receipt.lookup() == .missing)
    }

    @Test func cancellationAfterNativePrewarmDoesNotLoadOrRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        let task = Task {
            try await receipt.prepare(prewarm: { withUnsafeCurrentTask { $0?.cancel() } },
                                      loadAndValidate: { Issue.record("Unexpected load") })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(receipt.lookup() == .missing)
    }

    @Test func cancellationAfterNativeLoadDoesNotRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        let task = Task {
            try await receipt.prepare(prewarm: {}, loadAndValidate: { withUnsafeCurrentTask { $0?.cancel() } })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(receipt.lookup() == .missing)
    }

    @Test func greetingCountsButCannotRecordUntilValidatedLoad() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(scope: .stagedDecoder), file: file)
        #expect(receipt.needsPrewarm())
        // The real greeting owns native prewarm, then sets its in-memory marker only.
        let greetingCompleted = true
        #expect(!receipt.needsPrewarm(alreadyPrewarmed: greetingCompleted))
        #expect(receipt.lookup() == .missing)
        var prewarms = 0, loads = 0
        let first = try await receipt.prepare(alreadyPrewarmed: greetingCompleted,
            prewarm: { prewarms += 1 }, loadAndValidate: { loads += 1 })
        let second = try await receipt.prepare(prewarm: { prewarms += 1 }, loadAndValidate: { loads += 1 })
        #expect(!first.didPrewarm && first.receiptWritten && !second.didPrewarm)
        #expect(prewarms == 0 && loads == 2)
    }

    @Test func failedFirstTurnAfterGreetingDoesNotRecord() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(scope: .stagedDecoder), file: file)
        await #expect(throws: Failure.self) {
            _ = try await receipt.prepare(alreadyPrewarmed: true,
                prewarm: { Issue.record("Repeated greeting prewarm") },
                loadAndValidate: { throw Failure.expected })
        }
        #expect(receipt.lookup() == .missing)
    }

    @Test func diagnosticModesIgnoreProductionReceipts() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        _ = try await receipt.prepare(prewarm: {}, loadAndValidate: {})
        let data = try Data(contentsOf: file)
        var prewarms = 0
        _ = try await receipt.prepare(mode: .always, alreadyPrewarmed: true,
            prewarm: { prewarms += 1 }, loadAndValidate: {})
        _ = try await receipt.prepare(mode: .sessionOnly,
            prewarm: { prewarms += 1 }, loadAndValidate: {})
        _ = try await receipt.prepare(mode: .sessionOnly, alreadyPrewarmed: true,
            prewarm: { prewarms += 1 }, loadAndValidate: {})
        #expect(prewarms == 2)
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func diagnosticSuccessNeverSeedsProductionReceipt() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        let result = try await receipt.prepare(mode: .always, prewarm: {}, loadAndValidate: {})
        #expect(!result.receiptWritten && receipt.lookup() == .missing)
    }

    @Test func failedHitDoesNotErasePreviousSuccess() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        _ = try await receipt.prepare(prewarm: {}, loadAndValidate: {})
        let data = try Data(contentsOf: file)
        await #expect(throws: Failure.self) {
            _ = try await receipt.prepare(prewarm: { Issue.record("Unexpected prewarm") },
                                          loadAndValidate: { throw Failure.expected })
        }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func unwritableReceiptDoesNotFailSuccessfulModelLoad() async throws {
        let file = file(); defer { clean(file) }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let blocker = file.deletingLastPathComponent().appendingPathComponent("not-a-directory")
        try Data().write(to: blocker)
        let receipt = CoreMLPreparationReceipt(key: key(), file: blocker.appendingPathComponent("receipt.json"))
        let result = try await receipt.prepare(prewarm: {}, loadAndValidate: {})
        #expect(result.didPrewarm && !result.receiptWritten)
    }

    @Test func schemaMismatchIsAMiss() async throws {
        let file = file(); defer { clean(file) }
        let receipt = CoreMLPreparationReceipt(key: key(), file: file)
        _ = try await receipt.prepare(prewarm: {}, loadAndValidate: {})
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["schema"] = 999
        try JSONSerialization.data(withJSONObject: json).write(to: file, options: .atomic)
        #expect(receipt.lookup() == .incompatible)
    }

    private actor Owner {
        private final class NativeOwner {
            var prewarms = 0
            var loads = 0
            func prewarm() async { prewarms += 1; await Task.yield() }
            func load() async { loads += 1; await Task.yield() }
        }
        func prepare(_ receipt: CoreMLPreparationReceipt) async throws -> (Int, Int) {
            let native = NativeOwner()
            for _ in 0..<2 {
                _ = try await receipt.prepare(prewarm: { await native.prewarm() },
                                               loadAndValidate: { await native.load() })
            }
            return (native.prewarms, native.loads)
        }
    }

    @Test func nativeOwnerStaysOnCallingActor() async throws {
        let file = file(); defer { clean(file) }
        let counts = try await Owner().prepare(CoreMLPreparationReceipt(key: key(), file: file))
        #expect(counts.0 == 1 && counts.1 == 2)
    }
}
