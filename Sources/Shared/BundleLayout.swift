import Foundation

/// Shared helper for locating the enclosing `.app` bundle from a path inside it
/// (an XPC service or extension's own bundle, or a resolved peer executable).
enum BundleLayout {
    /// Walks up from `url` to the nearest enclosing `.app` bundle root.
    static func enclosingAppBundlePath(for url: URL) -> String? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" { return current.path }
            current.deleteLastPathComponent()
        }
        return nil
    }
}
