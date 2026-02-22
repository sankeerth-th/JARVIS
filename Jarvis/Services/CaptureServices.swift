import Foundation
import AppKit
import Vision

final class ScreenshotService {
    enum ScreenshotError: Error {
        case windowNotFound
        case captureFailed
    }

    func captureActiveWindow() throws -> NSImage {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let target = infoList.first(where: { ($0[kCGWindowLayer as String] as? Int) == 0 }),
              let windowID = target[kCGWindowNumber as String] as? CGWindowID else {
            throw ScreenshotError.windowNotFound
        }
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .shouldBeOpaque]) else {
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func captureFullScreen() throws -> NSImage {
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func capture(selection rect: CGRect) throws -> NSImage {
        guard let cgImage = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution]) else {
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

final class OCRService {
    enum OCRError: Error {
        case cgImageUnavailable
    }

    func recognizeText(from image: NSImage) throws -> String {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageUnavailable
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en_US"]
        request.recognitionLevel = .accurate
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let lines = observations.map { $0.topCandidates(1).first?.string ?? "" }
        return lines.joined(separator: "\n")
    }
}
