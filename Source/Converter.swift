import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

enum ImageFormat: String, CaseIterable, Sendable {
    case jpg = "JPG", png = "PNG", heic = "HEIC", pdf = "PDF"
    var suffix: String { rawValue.lowercased() }
    var type: CFString { (self == .jpg ? UTType.jpeg.identifier : self == .heic ? UTType.heic.identifier : UTType.png.identifier) as CFString }
}

struct ConversionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum Converter {
    @concurrent static func convert(_ input: URL, to format: ImageFormat, quality: Double, folder: URL) async throws -> [URL] {
        guard input.isFileURL, folder.isFileURL else { throw ConversionError(message: "Pilih file dan folder lokal.") }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("Convy-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        var outputs: [URL] = []
        var finished = false
        defer {
            try? FileManager.default.removeItem(at: temporary)
            if !finished { for output in outputs { try? FileManager.default.removeItem(at: output) } }
        }
        let stem = input.deletingPathExtension().lastPathComponent + "-converted"
        if input.pathExtension.lowercased() == "pdf" {
            guard format != .pdf else { throw ConversionError(message: "File sudah PDF. Pilih JPG, PNG, atau HEIC.") }
            guard let document = CGPDFDocument(input as CFURL), document.isUnlocked, document.numberOfPages > 0 else {
                throw ConversionError(message: "PDF rusak atau terkunci. Buka kunci PDF terlebih dahulu.")
            }
            for number in 1...document.numberOfPages {
                try Task.checkCancellation()
                let output = try autoreleasepool {
                    guard let page = document.page(at: number) else { throw ConversionError(message: "Halaman PDF tidak dapat dibaca.") }
                    let box = page.getBoxRect(.cropBox)
                    let rotated = abs(page.rotationAngle % 180) == 90
                    let width = ceil((rotated ? box.height : box.width) * 2)
                    let height = ceil((rotated ? box.width : box.height) * 2)
                    guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 20000, height <= 20000,
                        width * height <= 80000000 else { throw ConversionError(message: "Halaman PDF terlalu besar untuk dirender pada 144 DPI.") }
                    guard let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                        throw ConversionError(message: "Memori tidak cukup untuk halaman PDF.")
                    }
                    let rect = CGRect(x: 0, y: 0, width: width, height: height)
                    context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
                    context.concatenate(page.getDrawingTransform(.cropBox, rect: rect, rotate: 0, preserveAspectRatio: true))
                    context.drawPDFPage(page)
                    guard let image = context.makeImage() else { throw ConversionError(message: "Gagal merender halaman PDF.") }
                    return try save(image, format: format, quality: quality, folder: folder, temporary: temporary,
                        stem: stem + String(format: "-page-%03d", number))
                }
                outputs.append(output)
            }
        } else {
            let image = try readImage(input)
            outputs.append(try save(image, format: format, quality: quality, folder: folder, temporary: temporary, stem: stem))
        }
        finished = true
        return outputs
    }

    private static func readImage(_ input: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, nil) else {
            throw ConversionError(message: "File tidak dapat dibaca sebagai gambar.")
        }
        guard CGImageSourceGetCount(source) == 1 else {
            throw ConversionError(message: "Gambar animasi atau multi-frame belum didukung.")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        guard let width = properties?[kCGImagePropertyPixelWidth] as? Int,
              let height = properties?[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20000, height <= 20000, width <= 80000000 / height else {
            throw ConversionError(message: "Ukuran gambar terlalu besar (maksimal 80 megapiksel / sisi 20.000 px).")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: max(width, height)]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError(message: "Gambar rusak atau format tidak didukung Mac ini.")
        }
        return image
    }

    private static func save(_ source: CGImage, format: ImageFormat, quality: Double, folder: URL, temporary: URL, stem: String) throws -> URL {
        var image = source
        if format == .jpg {
            guard let context = CGContext(data: nil, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ConversionError(message: "Memori tidak cukup untuk gambar ini.")
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            guard let flattened = context.makeImage() else { throw ConversionError(message: "Gagal menyiapkan JPG.") }
            image = flattened
        }
        let result = temporary.appendingPathComponent(UUID().uuidString + "." + format.suffix)
        if format == .pdf {
            var rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            guard let consumer = CGDataConsumer(url: result as CFURL),
                let context = CGContext(consumer: consumer, mediaBox: &rect, nil) else {
                throw ConversionError(message: "Gagal membuat PDF.")
            }
            context.beginPDFPage(nil)
            context.draw(image, in: rect)
            context.endPDFPage(); context.closePDF()
            guard CGPDFDocument(result as CFURL)?.numberOfPages == 1 else { throw ConversionError(message: "PDF gagal disimpan.") }
        } else {
            guard let destination = CGImageDestinationCreateWithURL(result as CFURL, format.type, 1, nil) else {
                throw ConversionError(message: "Format keluaran tidak tersedia di Mac ini.")
            }
            CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: min(1, max(0.1, quality))] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ConversionError(message: "Gagal menyimpan gambar.") }
        }
        for index in 0..<10000 {
            let name = stem + (index == 0 ? "" : "-\(index)") + "." + format.suffix
            let output = folder.appendingPathComponent(name)
            do {
                try FileManager.default.copyItem(at: result, to: output)
                return output
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                continue
            }
        }
        throw ConversionError(message: "Terlalu banyak file bernama sama. Pilih folder lain.")
    }
}
