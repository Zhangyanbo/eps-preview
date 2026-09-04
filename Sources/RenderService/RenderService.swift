import Foundation

/// Does the actual EPS → PDF conversion by shelling out to Ghostscript.
///
/// Runs inside the *unsandboxed* XPC service. It receives the EPS *bytes*
/// (not a path) from the extension and writes them to its own temp file —
/// this keeps it from ever touching the user's original file location (which
/// it has no TCC grant for), while still giving Ghostscript a real, seekable
/// file (needed for binary DOS-EPS files that carry a preview header).
///
/// Ghostscript is located in this order:
///   1. a self-contained copy bundled in the host app's `Contents/Helpers/gs`
///      (used by downloaded release builds — no Homebrew required), then
///   2. a system install (Homebrew / MacPorts), for build-from-source users.
final class RenderService: NSObject, RenderProtocol {

    /// A resolved Ghostscript: the executable plus any environment it needs
    /// (the bundled copy needs GS_LIB pointing at its resource files).
    private struct Ghostscript {
        let executablePath: String
        let environment: [String: String]
    }

    private static let systemCandidates = [
        "/opt/homebrew/bin/gs",   // Apple-silicon Homebrew
        "/usr/local/bin/gs",      // Intel Homebrew
        "/opt/local/bin/gs",      // MacPorts
        "/usr/bin/gs",
    ]

    func renderEPSToPDF(epsData: Data, withReply reply: @escaping (Data?, String?) -> Void) {
        guard let gs = Self.locateGhostscript() else {
            reply(nil, "Ghostscript not found. Install it with: brew install ghostscript")
            return
        }

        let stem = UUID().uuidString
        let inputPath = NSTemporaryDirectory() + "eps-in-" + stem + ".eps"
        let outputPath = NSTemporaryDirectory() + "eps-out-" + stem + ".pdf"
        defer {
            try? FileManager.default.removeItem(atPath: inputPath)
            try? FileManager.default.removeItem(atPath: outputPath)
        }

        do {
            try epsData.write(to: URL(fileURLWithPath: inputPath))
        } catch {
            reply(nil, "Could not stage EPS for rendering: \(error.localizedDescription)")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gs.executablePath)
        process.environment = gs.environment
        process.arguments = [
            "-dNOPAUSE", "-dBATCH", "-dQUIET",
            "-dSAFER",                 // sandbox Ghostscript's own file/IO ops
            "-dEPSCrop",               // crop to the EPS BoundingBox
            "-dAutoRotatePages=/None", // keep the figure's authored orientation
            "-sDEVICE=pdfwrite",
            "-dCompatibilityLevel=1.4",
            "-sOutputFile=" + outputPath,
            inputPath,
        ]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()   // discard stdout

        do {
            try process.run()
        } catch {
            reply(nil, "Failed to launch Ghostscript: \(error.localizedDescription)")
            return
        }
        process.waitUntilExit()

        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8) ?? "unknown error"
            reply(nil, "Ghostscript exited with status \(process.terminationStatus). "
                + String(message.prefix(600)))
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: outputPath)),
              !data.isEmpty else {
            reply(nil, "Ghostscript reported success but produced no PDF output.")
            return
        }

        reply(data, nil)
    }

    // MARK: - Locating Ghostscript

    private static func locateGhostscript() -> Ghostscript? {
        if let bundled = bundledGhostscript() { return bundled }
        let baseEnv = ProcessInfo.processInfo.environment
        for path in systemCandidates where FileManager.default.isExecutableFile(atPath: path) {
            return Ghostscript(executablePath: path, environment: baseEnv)
        }
        return nil
    }

    /// Looks for a self-contained Ghostscript at `<HostApp>.app/Contents/Helpers/gs/`.
    private static func bundledGhostscript() -> Ghostscript? {
        guard let appPath = BundleLayout.enclosingAppBundlePath(for: Bundle.main.bundleURL) else {
            return nil
        }
        let url = URL(fileURLWithPath: appPath)

        let binary = url.appendingPathComponent("Contents/Helpers/gs/converter")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else { return nil }

        // Resources live under Contents/Resources/ (codesign refuses to seal a
        // big loose data tree that sits alongside Mach-O binaries).
        let share = url.appendingPathComponent("Contents/Resources/ghostscript", isDirectory: true)
        let gsLib = [
            share.appendingPathComponent("Resource/Init").path,
            share.appendingPathComponent("lib").path,
            share.appendingPathComponent("Resource/Font").path,
        ].joined(separator: ":")

        var env = ProcessInfo.processInfo.environment
        env["GS_LIB"] = gsLib
        return Ghostscript(executablePath: binary.path, environment: env)
    }
}
