import Foundation
import Security

/// XPC service entry point. `NSXPCListener.service()` runs the service event
/// loop and never returns.
final class ServiceDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        guard Self.isTrustedPeer(pid: newConnection.processIdentifier) else {
            return false
        }
        newConnection.exportedInterface = NSXPCInterface(with: RenderProtocol.self)
        newConnection.exportedObject = RenderService()
        newConnection.resume()
        return true
    }

    /// Restricts connections to processes that are part of *this same app
    /// bundle* (the Host app and its two Quick Look extensions).
    ///
    /// Release builds are ad-hoc signed (no Apple Developer Team ID), so we
    /// can't pin to a shared Team ID the way a notarized app would. Instead
    /// we require the peer's code signature to be internally consistent
    /// (unmodified since signing) *and* its on-disk executable to live inside
    /// the same `.app` bundle as this service. That's enough to reject an
    /// unrelated local process that merely guessed the mach service name,
    /// which is the actual gap this closes.
    private static func isTrustedPeer(pid: pid_t) -> Bool {
        guard let ownAppRoot = enclosingAppBundlePath(for: Bundle.main.bundleURL) else {
            return false
        }

        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let peerCode = code else {
            return false
        }
        guard SecCodeCheckValidity(peerCode, [], nil) == errSecSuccess else {
            return false
        }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(peerCode, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return false
        }
        var pathRef: CFURL?
        guard SecCodeCopyPath(staticCode, [], &pathRef) == errSecSuccess,
              let peerPath = pathRef as URL? else {
            return false
        }
        guard let peerAppRoot = enclosingAppBundlePath(for: peerPath) else {
            return false
        }
        return peerAppRoot == ownAppRoot
    }

    /// Walks up from `url` to the nearest enclosing `.app` bundle root.
    private static func enclosingAppBundlePath(for url: URL) -> String? {
        var current = url
        while current.path != "/" {
            if current.pathExtension == "app" { return current.path }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

let delegate = ServiceDelegate()
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()
