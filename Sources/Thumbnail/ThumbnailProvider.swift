import AppKit
import PDFKit
import QuickLookThumbnailing

/// Finder / Spotlight thumbnail extension. Renders the EPS to PDF (via the
/// embedded RenderService), rasterizes the first page, and hands the image
/// back to Quick Look as a file.
final class ThumbnailProvider: QLThumbnailProvider {

    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        RenderClient.render(fileURL: request.fileURL) { data, interpolate, errorMessage in
            func fail(_ message: String) {
                handler(nil, NSError(domain: "com.zhangyanbo.EPSPreview", code: 1,
                                     userInfo: [NSLocalizedDescriptionKey: message]))
            }

            guard let data,
                  let document = PDFDocument(data: data),
                  let page = document.page(at: 0),
                  let cgPage = page.pageRef else {
                fail(errorMessage ?? "Thumbnail render failed")
                return
            }

            let box = page.bounds(for: .mediaBox)
            guard box.width > 0, box.height > 0 else { fail("Empty page"); return }

            // Fit into the requested maximum, preserving aspect, at device scale.
            let maximum = request.maximumSize
            let fit = min(maximum.width / box.width, maximum.height / box.height)
            let pxW = max(Int((box.width * fit * request.scale).rounded()), 1)
            let pxH = max(Int((box.height * fit * request.scale).rounded()), 1)

            guard let context = CGContext(
                data: nil, width: pxW, height: pxH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                fail("Could not create bitmap context"); return
            }

            // White page background (documents render on white).
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: pxW, height: pxH))

            // Honor the source's interpolation intent (see RenderClient).
            context.interpolationQuality = interpolate ? .high : .none

            context.scaleBy(x: CGFloat(pxW) / box.width, y: CGFloat(pxH) / box.height)
            context.translateBy(x: -box.origin.x, y: -box.origin.y)
            context.drawPDFPage(cgPage)

            guard let cgImage = context.makeImage() else {
                fail("Could not rasterize page"); return
            }
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                fail("Could not encode thumbnail"); return
            }

            let outURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("epsthumb-\(UUID().uuidString).png")
            do {
                try png.write(to: outURL)
            } catch {
                fail("Could not write thumbnail: \(error.localizedDescription)")
                return
            }

            handler(QLThumbnailReply(imageFileURL: outURL), nil)
        }
    }
}
