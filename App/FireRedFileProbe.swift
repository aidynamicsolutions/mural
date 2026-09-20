#if MURAL_FIRERED_FILE_PROBE
import SwiftUI

/// Compiled only by the explicit file-probe project variant. No capture or Talk connection.
struct FireRedFileProbe: UIViewControllerRepresentable {
    static var requested: Bool {
        ProcessInfo.processInfo.arguments.contains("--run-firered")
    }

    func makeUIViewController(context: Context) -> UIViewController {
        MuralFireRedProbeViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}
#endif
