import Foundation
import XCTest

/// Loads JSON fixtures from the test bundle (Xcode) or `Bundle.module` (SwiftPM on Linux).
enum FixtureLoader {
    static func data(_ name: String, ext: String = "json") throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        if let url = bundle.url(forResource: name, withExtension: ext) {
            return try Data(contentsOf: url)
        }
        // Fallback to the source tree; works in the simulator, which can read host files.
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).\(ext)")
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(T.self, from: data(name))
    }
}

private final class BundleToken {}
