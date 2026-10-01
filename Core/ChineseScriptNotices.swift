import Foundation

public enum ChineseScriptNotices {
    public static func read() throws -> String {
        guard let url = Bundle.module.url(forResource: "opencc-notices", withExtension: "txt") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
