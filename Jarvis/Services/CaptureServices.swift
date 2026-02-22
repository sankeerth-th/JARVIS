import Foundation
import AppKit
import Vision

final class ScreenshotService {
    enum ScreenshotError: LocalizedError {
        case windowNotFound
        case captureFailed
        case screenPermissionMissing

        var errorDescription: String? {
            switch self {
            case .windowNotFound:
                return "No active window was found to capture."
            case .captureFailed:
                return "Screen capture failed."
            case .screenPermissionMissing:
                return "Screen Recording permission is missing or not yet applied. Grant it in Settings, then fully quit and reopen Jarvis."
            }
        }
    }

    private var hasPromptedForScreenCapture = false

    func captureActiveWindow() throws -> NSImage {
        promptForScreenCaptureIfNeeded()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let frontmostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let target = infoList.first(where: { info in
                  guard (info[kCGWindowLayer as String] as? Int) == 0,
                        (info[kCGWindowOwnerPID as String] as? pid_t) != currentPID,
                        (info[kCGWindowAlpha as String] as? Double ?? 1.0) > 0.01 else {
                      return false
                  }
                  if let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                     let frontmostPID,
                     ownerPID == frontmostPID {
                      return true
                  }
                  guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                        let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
                      return false
                  }
                  return rect.width > 120 && rect.height > 80
              }),
              let windowID = target[kCGWindowNumber as String] as? CGWindowID else {
            if !hasScreenCapturePermission() {
                throw ScreenshotError.screenPermissionMissing
            }
            throw ScreenshotError.windowNotFound
        }
        guard let cgImage = CGWindowListCreateImage(.null, .optionIncludingWindow, windowID, [.boundsIgnoreFraming, .shouldBeOpaque]) else {
            if !hasScreenCapturePermission() {
                throw ScreenshotError.screenPermissionMissing
            }
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func captureFullScreen() throws -> NSImage {
        promptForScreenCaptureIfNeeded()
        guard let image = CGDisplayCreateImage(CGMainDisplayID()) else {
            if !hasScreenCapturePermission() {
                throw ScreenshotError.screenPermissionMissing
            }
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func capture(selection rect: CGRect) throws -> NSImage {
        promptForScreenCaptureIfNeeded()
        guard let cgImage = CGWindowListCreateImage(rect, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution]) else {
            if !hasScreenCapturePermission() {
                throw ScreenshotError.screenPermissionMissing
            }
            throw ScreenshotError.captureFailed
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func hasScreenCapturePermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    private func promptForScreenCaptureIfNeeded() {
        guard !hasScreenCapturePermission() else { return }
        guard !hasPromptedForScreenCapture else { return }
        hasPromptedForScreenCapture = true
        _ = CGRequestScreenCaptureAccess()
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
