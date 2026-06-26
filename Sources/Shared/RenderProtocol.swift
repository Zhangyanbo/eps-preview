import Foundation

/// XPC interface between the (sandboxed) Quick Look / Thumbnail extensions
/// and the (unsandboxed) RenderService.
///
/// IMPORTANT: we pass the EPS file's *bytes*, not its path. The extension is
/// the process that the system grants read access to the previewed file
/// (including files in TCC-protected locations like ~/Downloads, ~/Desktop,
/// ~/Documents). The separate RenderService process has no such grant, so it
/// must never open the original path itself — it writes the bytes we hand it
/// to its own temp file and runs Ghostscript on that.
@objc protocol RenderProtocol {
    func renderEPSToPDF(epsData: Data, withReply reply: @escaping (Data?, String?) -> Void)
}
