import Cocoa
import PDFKit
import Quartz

/// Quick Look preview extension. macOS instantiates this in a sandboxed
/// `com.apple.quicklook.preview` process when the user presses space on an
/// `.eps` / `.ps` file in Finder.
///
/// Rendering is delegated to the embedded (unsandboxed) RenderService, which
/// returns the figure as PDF data. We display it edge-to-edge in a PDFView.
final class PreviewViewController: NSViewController, QLPreviewingController {

    private let pdfView: PDFView = {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.backgroundColor = .clear
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let errorLabel: NSTextField = {
        let label = NSTextField(labelWithString: "")
        label.alignment = .center
        label.maximumNumberOfLines = 0
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.isHidden = true
        return label
    }()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        root.addSubview(pdfView)
        root.addSubview(errorLabel)

        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: root.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            errorLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            errorLabel.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            errorLabel.widthAnchor.constraint(lessThanOrEqualTo: root.widthAnchor, multiplier: 0.85),
        ])

        view = root
        preferredContentSize = NSSize(width: 1024, height: 768)
    }

    func preparePreviewOfFile(at url: URL,
                              completionHandler handler: @escaping (Error?) -> Void) {
        RenderClient.render(fileURL: url) { [weak self] data, interpolate, errorMessage in
            DispatchQueue.main.async {
                guard let self else { return }
                if let data, let document = PDFDocument(data: data) {
                    for i in 0..<document.pageCount { document.page(at: i)?.rotation = 0 }
                    // Honor the source's interpolation intent: nearest-neighbour
                    // by default (keeps pixel figures crisp), smoothing only when
                    // the EPS explicitly asked for it.
                    self.pdfView.interpolationQuality = interpolate ? .high : .none
                    self.pdfView.document = document
                    self.pdfView.isHidden = false
                    self.errorLabel.isHidden = true
                    handler(nil)
                } else {
                    // Surface the error in-panel AND report it, so the user
                    // sees why (e.g. Ghostscript missing) rather than a blank.
                    self.pdfView.isHidden = true
                    self.errorLabel.stringValue = errorMessage ?? "Could not render this EPS file."
                    self.errorLabel.isHidden = false
                    handler(nil)
                }
            }
        }
    }
}
