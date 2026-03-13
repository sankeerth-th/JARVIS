import Foundation
import AppKit
import Vision
import CoreImage
import ScreenCaptureKit

final class ScreenshotService {
    enum ScreenshotError: LocalizedError {
        case windowNotFound
        case captureFailed
        case screenPermissionMissing
        case captureNotAvailable

        var errorDescription: String? {
            switch self {
            case .windowNotFound:
                return "No active window was found to capture."
            case .captureFailed:
                return "Screen capture failed. Try again after confirming Screen Recording access in System Settings."
            case .screenPermissionMissing:
                return "Screen recording permission is denied or unavailable. Open System Settings and allow Jarvis in Privacy & Security > Screen Recording."
            case .captureNotAvailable:
                return "Screen capture is not available on this device."
            }
        }
    }

    private let permissionsManager: PermissionsManager

    init(permissionsManager: PermissionsManager = .shared) {
        self.permissionsManager = permissionsManager
    }

    @MainActor
    func captureActiveWindow() async throws -> NSImage {
        guard hasScreenCapturePermission() else {
            throw ScreenshotError.screenPermissionMissing
        }

        do {
            let content = try await SCShareableContent.current
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier

            guard let window = content.windows.first(where: { window in
                guard window.owningApplication?.processID != currentPID,
                      window.isOnScreen,
                      !(window.title?.isEmpty ?? true) else {
                    return false
                }
                if let frontmostPID = frontmostPID,
                   window.owningApplication?.processID == frontmostPID {
                    return true
                }
                return window.frame.width > 120 && window.frame.height > 80
            }) else {
                throw ScreenshotError.windowNotFound
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            try throwIfScreenCapturePermissionMissing()
            throw ScreenshotError.captureFailed
        }
    }

    @MainActor
    func captureFullScreen() async throws -> NSImage {
        guard hasScreenCapturePermission() else {
            throw ScreenshotError.screenPermissionMissing
        }

        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw ScreenshotError.captureNotAvailable
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            try throwIfScreenCapturePermissionMissing()
            throw ScreenshotError.captureFailed
        }
    }

    @MainActor
    func capture(selection rect: CGRect) async throws -> NSImage {
        guard hasScreenCapturePermission() else {
            throw ScreenshotError.screenPermissionMissing
        }

        do {
            let content = try await SCShareableContent.current
            guard let display = content.displays.first else {
                throw ScreenshotError.captureNotAvailable
            }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.showsCursor = false
            config.sourceRect = rect

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        } catch {
            try throwIfScreenCapturePermissionMissing()
            throw ScreenshotError.captureFailed
        }
    }

    private func hasScreenCapturePermission() -> Bool {
        permissionsManager.checkScreenCapturePermission()
    }

    private func refreshScreenCapturePermission() -> Bool {
        permissionsManager.checkScreenCapturePermission(forceRefresh: true)
    }

    private func throwIfScreenCapturePermissionMissing() throws {
        if !refreshScreenCapturePermission() {
            throw ScreenshotError.screenPermissionMissing
        }
    }
}

final class OCRService {
    enum OCRError: Error {
        case cgImageUnavailable
    }

    struct OCRLine: Equatable {
        var text: String
        var confidence: Double
    }

    struct OCRResult: Equatable {
        var text: String
        var lines: [OCRLine]
        var averageConfidence: Double
    }

    private let ciContext = CIContext(options: nil)

    func recognize(from image: NSImage, applyPreprocessing: Bool = true) throws -> OCRResult {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw OCRError.cgImageUnavailable
        }
        let cgImage = applyPreprocessing ? (preprocess(cgImage: sourceImage) ?? sourceImage) : sourceImage
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["en_US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        let observations = request.results ?? []
        let lines: [OCRLine] = observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, confidence: Double(candidate.confidence))
        }
        let average = lines.isEmpty ? 0 : (lines.reduce(0) { $0 + $1.confidence } / Double(lines.count))
        return OCRResult(text: lines.map(\.text).joined(separator: "\n"), lines: lines, averageConfidence: average)
    }

    func recognizeText(from image: NSImage) throws -> String {
        try recognize(from: image, applyPreprocessing: true).text
    }

    private func preprocess(cgImage: CGImage) -> CGImage? {
        let ciImage = CIImage(cgImage: cgImage)
        guard let grayscale = CIFilter(name: "CIPhotoEffectMono") else {
            return nil
        }
        grayscale.setValue(ciImage, forKey: kCIInputImageKey)
        guard let monochrome = grayscale.outputImage else { return nil }

        guard let colorControls = CIFilter(name: "CIColorControls") else {
            return nil
        }
        colorControls.setValue(monochrome, forKey: kCIInputImageKey)
        colorControls.setValue(1.1, forKey: kCIInputContrastKey)
        colorControls.setValue(0.0, forKey: kCIInputSaturationKey)
        guard let adjusted = colorControls.outputImage else { return nil }

        return ciContext.createCGImage(adjusted, from: adjusted.extent)
    }
}
