import Foundation
import Combine

public struct StreamingPipelineCompletion: Equatable {
    public let finalText: String
    public let streamedChunks: [String]

    public init(finalText: String, streamedChunks: [String]) {
        self.finalText = finalText
        self.streamedChunks = streamedChunks
    }
}

public struct StreamingBuffer {
    private var pendingText: String = ""
    private let sentenceDelimiters: CharacterSet
    private let minFlushLength: Int
    private let maxPendingLength: Int

    public init(
        minFlushLength: Int = 20,
        maxPendingLength: Int = 100
    ) {
        self.minFlushLength = minFlushLength
        self.maxPendingLength = maxPendingLength
        self.sentenceDelimiters = CharacterSet(charactersIn: ".!?\n")
    }

    public mutating func ingest(_ text: String) -> String? {
        pendingText.append(text)
        guard shouldFlush() else { return nil }
        return flush()
    }

    public mutating func finish() -> String? {
        guard !pendingText.isEmpty else { return nil }
        return flush()
    }

    public mutating func reset() {
        pendingText = ""
    }

    private func shouldFlush() -> Bool {
        if pendingText.count >= maxPendingLength {
            return true
        }

        if pendingText.count >= minFlushLength,
           let lastScalar = pendingText.unicodeScalars.last,
           sentenceDelimiters.contains(lastScalar) {
            return true
        }

        if pendingText.hasSuffix(" "), pendingText.count >= minFlushLength {
            return pendingText.split(separator: " ").count >= 3
        }

        return false
    }

    private mutating func flush() -> String {
        let flushed = pendingText
        pendingText = ""
        return flushed
    }
}

@MainActor
public final class StreamingPipeline: ObservableObject {
    public struct Configuration {
        public var enableBuffering: Bool
        public var enableSentenceFlushing: Bool
        public var minFlushInterval: TimeInterval
        public var maxBufferSize: Int
        public var minFlushLength: Int
        public var maxPendingLength: Int
        public var enableJitterReduction: Bool
        public var jitterReductionDelay: TimeInterval

        public init(
            enableBuffering: Bool = true,
            enableSentenceFlushing: Bool = true,
            minFlushInterval: TimeInterval = 0.03,
            maxBufferSize: Int = 8,
            minFlushLength: Int = 15,
            maxPendingLength: Int = 80,
            enableJitterReduction: Bool = true,
            jitterReductionDelay: TimeInterval = 0.02
        ) {
            self.enableBuffering = enableBuffering
            self.enableSentenceFlushing = enableSentenceFlushing
            self.minFlushInterval = minFlushInterval
            self.maxBufferSize = maxBufferSize
            self.minFlushLength = minFlushLength
            self.maxPendingLength = maxPendingLength
            self.enableJitterReduction = enableJitterReduction
            self.jitterReductionDelay = jitterReductionDelay
        }

        public static let `default` = Configuration()
        public static let responsive = Configuration(
            enableBuffering: false,
            enableSentenceFlushing: true,
            minFlushInterval: 0.01,
            maxBufferSize: 3,
            minFlushLength: 5,
            maxPendingLength: 30
        )
        public static let smooth = Configuration(
            enableBuffering: true,
            enableSentenceFlushing: true,
            minFlushInterval: 0.08,
            maxBufferSize: 12,
            minFlushLength: 25,
            maxPendingLength: 120,
            enableJitterReduction: true,
            jitterReductionDelay: 0.05
        )
    }

    @Published public private(set) var bufferedTokenCount: Int = 0
    @Published public private(set) var totalTokensReceived: Int = 0
    @Published public private(set) var totalTokensFlushed: Int = 0

    private var configuration: Configuration
    private var streamingBuffer: StreamingBuffer
    private var tokenBuffer: [String] = []
    private var lastFlushTime: Date = .distantPast
    private var canonicalText: String = ""
    private var emittedChunks: [String] = []

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.streamingBuffer = StreamingBuffer(
            minFlushLength: configuration.minFlushLength,
            maxPendingLength: configuration.maxPendingLength
        )
    }

    public var authoritativeText: String {
        canonicalText
    }

    public func ingest(_ token: String) -> [String] {
        totalTokensReceived += 1

        if configuration.enableBuffering {
            tokenBuffer.append(token)
            bufferedTokenCount = tokenBuffer.count
            guard shouldFlushTokenBuffer() else { return [] }
            return flushTokenBuffer()
        }

        return processCombinedText(token)
    }

    public func finish() -> StreamingPipelineCompletion {
        var finalChunks = flushTokenBuffer()
        if let trailing = streamingBuffer.finish() {
            finalChunks.append(commit(trailing))
        }
        bufferedTokenCount = 0
        return StreamingPipelineCompletion(
            finalText: canonicalText,
            streamedChunks: finalChunks
        )
    }

    public func reset() {
        streamingBuffer.reset()
        tokenBuffer.removeAll()
        lastFlushTime = .distantPast
        canonicalText = ""
        emittedChunks.removeAll()
        bufferedTokenCount = 0
        totalTokensReceived = 0
        totalTokensFlushed = 0
    }

    public func updateConfiguration(_ newConfiguration: Configuration) {
        configuration = newConfiguration
        streamingBuffer = StreamingBuffer(
            minFlushLength: newConfiguration.minFlushLength,
            maxPendingLength: newConfiguration.maxPendingLength
        )
        tokenBuffer.removeAll()
        bufferedTokenCount = 0
        lastFlushTime = .distantPast
    }

    private func shouldFlushTokenBuffer() -> Bool {
        guard !tokenBuffer.isEmpty else { return false }
        if tokenBuffer.count >= configuration.maxBufferSize {
            return true
        }
        return Date().timeIntervalSince(lastFlushTime) >= configuration.minFlushInterval
    }

    private func flushTokenBuffer() -> [String] {
        guard !tokenBuffer.isEmpty else { return [] }
        let combined = tokenBuffer.joined()
        tokenBuffer.removeAll()
        bufferedTokenCount = 0
        lastFlushTime = Date()
        return processCombinedText(combined)
    }

    private func processCombinedText(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }

        if !configuration.enableSentenceFlushing {
            return [commit(text)]
        }

        guard let flushed = streamingBuffer.ingest(text) else { return [] }
        return [commit(flushed)]
    }

    private func commit(_ text: String) -> String {
        canonicalText.append(text)
        emittedChunks.append(text)
        totalTokensFlushed += 1
        return text
    }

    public func createStreamCoordinator(
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) -> StreamCoordinator {
        StreamCoordinator(
            pipeline: self,
            onToken: onToken,
            onComplete: onComplete
        )
    }
}

@MainActor
public final class StreamCoordinator {
    private let pipeline: StreamingPipeline
    private let onToken: (String) -> Void
    private let onComplete: () -> Void

    public init(
        pipeline: StreamingPipeline,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.pipeline = pipeline
        self.onToken = onToken
        self.onComplete = onComplete
    }

    public func start() {}

    public func ingest(_ token: String) {
        for text in pipeline.ingest(token) {
            onToken(text)
        }
    }

    public func finish() {
        let completion = pipeline.finish()
        for chunk in completion.streamedChunks {
            onToken(chunk)
        }
        onComplete()
    }

    public func cancel() {
        pipeline.reset()
    }
}

extension StreamingPipeline {
    public func createAsyncStream(
        from source: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor in
                do {
                    for try await token in source {
                        for text in self.ingest(token) {
                            continuation.yield(text)
                        }
                    }

                    let completion = self.finish()
                    for chunk in completion.streamedChunks {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
