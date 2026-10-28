import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers

@main struct Tests {
    static func main() async throws {
        precondition(WheelGeometry.sector(at: CGPoint(x: 140, y: 238)) == 0)
        precondition(WheelGeometry.sector(at: CGPoint(x: 238, y: 140)) == 1)
        precondition(WheelGeometry.sector(at: CGPoint(x: 140, y: 42)) == 2)
        precondition(WheelGeometry.sector(at: CGPoint(x: 42, y: 140)) == 3)
        precondition(WheelGeometry.sector(at: CGPoint(x: 140, y: 140)) == nil)
        precondition(WheelGeometry.sector(at: CGPoint(x: 0, y: 0)) == nil)
        precondition(WheelGeometry.sector(at: CGPoint(x: 210, y: 210)) == nil)
        let cornerAngle = CGFloat.pi / 4 + 0.025
        let removedCorner = CGPoint(x: 140 + 131.9 * cos(cornerAngle), y: 140 + 131.9 * sin(cornerAngle))
        precondition(WheelGeometry.sector(at: removedCorner) == nil)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Convy-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("Original image.png")
        let context = CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 24))
        let destination = CGImageDestinationCreateWithURL(input as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        let original = try Data(contentsOf: input)
        let formats = ImageFormat.allCases.filter { !CommandLine.arguments.contains("--skip-heic") || $0 != .heic }
        for format in formats {
            let output = try await Converter.convert(input, to: format, quality: 0.85, folder: root)[0]
            if format == .pdf {
                precondition(CGPDFDocument(output as CFURL)?.numberOfPages == 1)
            } else {
                let decoded = CGImageSourceCreateWithURL(output as CFURL, nil)!
                let image = CGImageSourceCreateImageAtIndex(decoded, 0, nil)!
                precondition(image.width == 32 && image.height == 24)
            }
            let second = try await Converter.convert(input, to: format, quality: 0.85, folder: root)[0]
            precondition(output != second && FileManager.default.fileExists(atPath: output.path))
            let roundtrip = try await Converter.convert(output, to: .png, quality: 1, folder: root)[0]
            precondition(FileManager.default.fileExists(atPath: roundtrip.path))
        }
        let unchanged = try Data(contentsOf: input)
        precondition(unchanged == original)
        let oriented = root.appendingPathComponent("rotated.jpg")
        let rotationDestination = CGImageDestinationCreateWithURL(oriented as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(rotationDestination, context.makeImage()!, [kCGImagePropertyOrientation: 6] as CFDictionary)
        precondition(CGImageDestinationFinalize(rotationDestination))
        let normalized = try await Converter.convert(oriented, to: .png, quality: 1, folder: root)[0]
        let normalizedSource = CGImageSourceCreateWithURL(normalized as CFURL, nil)!
        let normalizedImage = CGImageSourceCreateImageAtIndex(normalizedSource, 0, nil)!
        precondition(normalizedImage.width == 24 && normalizedImage.height == 32)
        let animated = root.appendingPathComponent("animated.gif")
        let animationDestination = CGImageDestinationCreateWithURL(animated as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        CGImageDestinationAddImage(animationDestination, context.makeImage()!, nil)
        CGImageDestinationAddImage(animationDestination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(animationDestination))
        do {
            _ = try await Converter.convert(animated, to: .png, quality: 1, folder: root)
            preconditionFailure("Animation silently flattened")
        } catch is ConversionError {}
        let invalid = root.appendingPathComponent("broken.png")
        try Data("not an image".utf8).write(to: invalid)
        do {
            _ = try await Converter.convert(invalid, to: .png, quality: 1, folder: root)
            preconditionFailure("Invalid image accepted")
        } catch is ConversionError {}
        let missing = root.appendingPathComponent("missing/folder")
        do {
            _ = try await Converter.convert(input, to: .jpg, quality: 1, folder: missing)
            preconditionFailure("Missing output folder accepted")
        } catch {}
        func pdf(_ name: String, hugeSecondPage: Bool = false, locked: Bool = false) -> URL {
            let url = root.appendingPathComponent(name + ".pdf")
            var box = CGRect(x: 0, y: 0, width: 32, height: 24)
            let consumer = CGDataConsumer(url: url as CFURL)!
            let options = locked ? [kCGPDFContextUserPassword: "secret", kCGPDFContextOwnerPassword: "owner"] as CFDictionary : nil
            let pdf = CGContext(consumer: consumer, mediaBox: &box, options)!
            for index in 0..<2 {
                var pageBox = index == 0 ? box : CGRect(x: 0, y: 0, width: hugeSecondPage ? 100000 : 20, height: 40)
                let data = withUnsafeBytes(of: &pageBox) { Data($0) }
                pdf.beginPDFPage([kCGPDFContextMediaBox: data] as CFDictionary)
                pdf.setFillColor(CGColor(red: index == 0 ? 1 : 0, green: 0, blue: index == 0 ? 0 : 1, alpha: 1))
                pdf.fill(pageBox); pdf.endPDFPage()
            }
            pdf.closePDF()
            return url
        }
        let document = pdf("Two pages")
        let pdfOriginal = try Data(contentsOf: document)
        let pages = try await Converter.convert(document, to: .jpg, quality: 0.9, folder: root)
        precondition(pages.count == 2)
        precondition(pages[0].lastPathComponent.contains("page-001"))
        precondition(pages[1].lastPathComponent.contains("page-002"))
        for (index, output) in pages.enumerated() {
            let source = CGImageSourceCreateWithURL(output as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            precondition(image.width == (index == 0 ? 64 : 40) && image.height == (index == 0 ? 48 : 80))
        }
        let secondPages = try await Converter.convert(document, to: .jpg, quality: 0.9, folder: root)
        precondition(Set(pages).isDisjoint(with: Set(secondPages)))
        let afterPDF = try Data(contentsOf: document)
        precondition(afterPDF == pdfOriginal)
        for invalidPDF in [pdf("Too large", hugeSecondPage: true), pdf("Locked", locked: true)] {
            do {
                _ = try await Converter.convert(invalidPDF, to: .jpg, quality: 1, folder: root)
                preconditionFailure("Invalid PDF accepted")
            } catch is ConversionError {}
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        precondition(!names.contains { $0.hasPrefix("Too large-converted") })
        do {
            _ = try await Converter.convert(document, to: .pdf, quality: 1, folder: root)
            preconditionFailure("PDF to PDF silently rasterized")
        } catch is ConversionError {}
        print("PASS: multi-page PDF to JPG, 144 DPI, page dimensions/names, duplicates, original PDF, locked PDF, oversized page rollback")
        print("PASS: wheel sectors/center/outside/gaps; \(formats.map(\.rawValue).joined(separator: ", ")); decode/roundtrip, dimensions, duplicate names, originals, EXIF orientation, animation rejection, invalid image, write failure")
    }
}
