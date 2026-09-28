import Foundation

public enum SpeechPackageCatalog {
    /// Reviewed metadata is compiled into the app, not obtained from the same download
    /// as its trust pin. Public availability/native qualification remains a separate gate.
    /// Keep previous trusted versions when adding a replacement for an active package.
    private static let fireRedManifest = Data(#"{"backend":"fireRedASR2Int8","computeUnits":{"recognizer":"cpu"},"files":[{"bytes":417291928,"downloadPath":"decoder.int8.onnx","path":"support/decoder.int8.onnx","sha256":"b840ce7196ae4a14d05ae84bbf56082b6b61ccec5610fda907dddbcea37354ff"},{"bytes":817286833,"downloadPath":"encoder.int8.onnx","path":"support/encoder.int8.onnx","sha256":"54048d66b6e8f3c80ea7ce95efe794587b0fd81d7271651d0decd3803852ae82"},{"bytes":79172,"downloadPath":"tokens.txt","path":"support/tokens.txt","sha256":"1bc613de2112d257e61a349c3e72d1b1a9cf19c33d3ca954197ad2171e5ea07b"}],"hardware":["iPhone18,3"],"id":"firered-asr2-int8-374cff18-v1","osMajors":[27],"pair":"zh-CN-en","revision":"374cff185e952c40fcf2f6da972a3b6cf340608d","schema":1,"specializationReserveBytes":0}"#.utf8)
    public static let entries: [ReviewedSpeechPackage] = [
        .init(id: "firered-asr2-int8-374cff18-v1", pair: .mainlandMandarinEnglish,
              bundledManifest: fireRedManifest,
              filesURL: URL(string: "https://huggingface.co/csukuangfj2/sherpa-onnx-fire-red-asr2-zh_en-int8-2026-02-26/resolve/374cff185e952c40fcf2f6da972a3b6cf340608d/")!,
              manifestSHA256: "a302683c199acb2b37e664fd8ba52d7a5d47503d49dfdff06ba861a264329e3d", allowedHosts: ["huggingface.co"])
    ]

    public static func entry(for pair: LocalSpeechPair) throws -> ReviewedSpeechPackage {
        guard let selected = entries.first(where: { $0.pair == pair }) else { throw SpeechPackageError.notPublished }
        guard Set(entries.map { $0.id }).count == entries.count else { throw SpeechPackageError.invalidManifest }
        for entry in entries { try entry.validate() }
        return selected
    }
}
