import SwiftUI
import MuralCore

/// Same disclosure in live transcript and history. No converter runs during view rendering.
struct TranscriptScriptDisclosure: View {
    let passage: Passage
    var body: some View {
        let originals = passage.fragments.filter { $0.hasScriptPresentation || ($0.revision > 0 && $0.rawASRText != nil) }
        if !originals.isEmpty {
            DisclosureGroup(passage.hasScriptPresentation ? "Simplified display · original recognition" : "Original recognition · edited wording") {
                ForEach(originals) { fragment in
                    if let raw = fragment.rawASRText {
                        Text(raw).font(.footnote).textSelection(.enabled)
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(MuralColor.secondary)
            .accessibilityIdentifier("transcript-script-original")
        }
    }
}
