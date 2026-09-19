#!/usr/bin/env python3
"""Compile the actual product config/parity helpers; check safe loading-only flags."""
from pathlib import Path
import subprocess
import tempfile

source = (Path(__file__).resolve().parents[2] / 'App/MuralApp.swift').read_text()
config = source.split('    fileprivate struct ProductConfig:', 1)[1].split('    fileprivate struct ProductMemory:', 1)[0]
types = source.split('    fileprivate struct ProductMemory:', 1)[1].split('    fileprivate struct ProductCancellation:', 1)[0]
parity = source.split('    private static func productRecoveryMatches', 1)[1].split('    private func productLoadOnly', 1)[0]
normalize = source.split('    private static func productNormalize', 1)[1].split('\n    }', 1)[0] + '\n    }\n'
engine = (Path(__file__).resolve().parents[2] / 'App/LocalConversationEngine.swift').read_text()
candidate = engine.split('    enum CompressionCandidate:', 1)[1].split('    static var enabled:', 1)[0]
policy = Path(__file__).with_name('DecoderTrialPolicy.swift').read_text()
swift = policy + '''import Foundation
struct ProbeError: Error { init(_ message: String) {} }
enum AIModel { static let deviceArchitectureName = "h18p" }
struct W8RuntimeIdentitySpec: Decodable, Sendable {
    let kind: String
    let format: String
    let transport: String
    init(from decoder: Decoder) throws {
        kind = "encoder"; format = "fp16"; transport = "packed"
    }
    func validate() throws {}
}
enum W8TinyProbe { static let fullManifestPins: [String: String] = [:] }
enum PhoWhisperStagedEncoder {
    typealias Failure = ProbeError
    static let enabled = true
    enum CompressionCandidate:''' + candidate + '''
    static func sha256(_ data: Data) -> String { "" }
    static func bundleBytes(_ url: URL) throws -> Int { 0 }
    static func fingerprint(_ url: URL, includeHiddenFiles: Bool = false) throws -> String { "" }
}
struct CoreAIPhoWhisper {
    static let productEncoderFingerprintByArchitecture = ["h18p": "bound"]
    static let productFrozenAudioSHA256 = ["001.wav": "frozen"]
    struct ProductConfig:''' + config + '    struct ProductMemory:' + types + '    static func productRecoveryMatches' + parity + '    static func productNormalize' + normalize + '''
}
let config: CoreAIPhoWhisper.ProductConfig
do { config = try CoreAIPhoWhisper.ProductConfig.resolve() }
catch { exit(2) }

let json = """
{"turn":1,"file":"001.wav","sampleCount":90560,"audioSHA256":"frozen",
"rawTranscript":"Yesterday I went to the supermarket.",
"normalizedTranscript":"yesterday i went to the supermarket","detectedLanguages":["vi"],
"generatedTokens":[[50258,50278,50359,50363,56,4690,286,1437,220,1353,220,3322,25180,13,50257]],
"segmentTokens":[],"melSHA256":[],"encoderHiddenSHA256":[],"thermalBefore":0,"thermalAfter":0,"termination":"endToken"}
"""
precondition(CoreAIPhoWhisper.productNormalize("CAFE\\u{301}, <tag> ① + yes!") == "café <tag> ① + yes")
precondition(CoreAIPhoWhisper.productNormalize("seal tea") != CoreAIPhoWhisper.productNormalize("seoul tea"))
let decoder = JSONDecoder()
let exact = try decoder.decode(CoreAIPhoWhisper.ProductTurn.self, from: Data(json.utf8))
precondition(CoreAIPhoWhisper.productRecoveryMatches(exact))
let changed = json.replacingOccurrences(of: "Yesterday", with: "Today")
let mismatch = try decoder.decode(CoreAIPhoWhisper.ProductTurn.self, from: Data(changed.utf8))
precondition(!CoreAIPhoWhisper.productRecoveryMatches(mismatch))
print("PASS")
'''
with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / 'check.swift'
    path.write_text(swift.replace('fileprivate ', ''))
    binary = Path(directory) / 'check'
    subprocess.run(['xcrun', 'swiftc', '-D', 'MURAL_COREAI_W8', str(path), '-o', str(binary)], check=True, timeout=60)
    for mode in ['encoder-only', 'encoder-gpu-only', 'decoder-only', 'encoder-rebuild-only', 'staged', 'staged-gpu']:
        subprocess.run([str(binary), f'--coreai-product-mode={mode}'], check=True, timeout=10)
    for mode in ['baseline', 'staged', 'staged-gpu']:
        subprocess.run([str(binary), f'--coreai-product-mode={mode}', '--coreai-product-corpus'], check=True, timeout=10)
    for mode in ['staged', 'staged-gpu']:
        for boundary in ['prepare', 'encoder', 'decoder']:
            subprocess.run([str(binary), f'--coreai-product-mode={mode}', f'--coreai-product-cancel-at={boundary}'], check=True, timeout=10)
        subprocess.run([str(binary), f'--coreai-product-mode={mode}', '--coreai-product-coexistence'], check=True, timeout=10)
    subprocess.run([str(binary), '--coreai-product-mode=staged-gpu-encode'], check=True, timeout=10)
    for candidate in ['original-pal8']:
        subprocess.run([str(binary), '--coreai-product-mode=staged-gpu', '--coreai-product-corpus',
                        '--coreai-compressed-encoder=' + candidate], check=True, timeout=10)
    # Rejected configurations must not reach any model loading/inference.
    for flags in [
        # Known AOT cache collision must fail before any model loading.
        *[['--coreai-product-mode=staged-gpu', '--coreai-compressed-encoder=' + c]
          for c in ['fp8', 'int8', 'fp8-pal8', 'int8-pal8']],
        ['--coreai-product-mode=staged-gpu-encode', '--coreai-product-corpus'],
        ['--coreai-product-mode=staged-gpu-encode', '--coreai-product-coexistence'],
        ['--coreai-product-mode=staged-gpu', '--coreai-compressed-encoder=unknown'],
        ['--coreai-product-mode=hybrid', '--coreai-compressed-encoder=fp8'],
        ['--coreai-product-mode=staged-gpu', '--coreai-compressed-encoder=fp8', '--coreai-compressed-encoder=int8'],
        ['--coreai-product-mode=encoder-only', '--coreai-product-turns=2'],
        ['--coreai-product-mode=decoder-only', '--coreai-product-corpus'],
        ['--coreai-product-mode=encoder-gpu-only', '--coreai-product-corpus'],
        ['--coreai-product-mode=encoder-gpu-only', '--coreai-product-turns=2'],
        ['--coreai-product-mode=encoder-gpu-only', '--coreai-product-cancel-at=encoder'],
        ['--coreai-product-mode=encoder-gpu-only', '--coreai-product-coexistence'],
        ['--coreai-product-mode=staged-gpu', '--coreai-product-turns=11'],
        ['--coreai-product-mode=staged-gpu', '--coreai-product-corpus', '--coreai-product-cancel-at=encoder'],
        ['--coreai-product-mode=staged-gpu', '--coreai-product-corpus', '--coreai-product-turns=2'],
        ['--coreai-product-cancel-at=unknown'],
        ['--coreai-product-mode=baseline', '--coreai-product-coexistence'],
        ['--coreai-product-mode=staged', '--coreai-product-turns=11'],
        ['--coreai-product-mode=staged', '--coreai-product-corpus', '--coreai-product-turns=2'],
        ['--coreai-product-mode=staged', '--coreai-product-corpus', '--coreai-product-cancel-at=encoder'],
        ['--coreai-product-cancel-at=encoder', '--coreai-product-sequence=002.wav'],
    ]:
        result = subprocess.run([str(binary), *flags], capture_output=True, timeout=10)
        assert result.returncode != 0, flags
print('PASS: loading-only constraints, real cancellation boundary flags, exact recovery parity')
