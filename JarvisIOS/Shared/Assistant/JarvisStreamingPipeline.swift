import Foundation
import Combine

// MARK: - Token Buffer

public actor TokenBuffer {
    private var buffer: [String] = []
    private var lastFlushTime: Date = Date()
    private let minFlushInterval: TimeInterval
    private let maxBufferSize: Int
    
    public init(
        minFlushInterval: TimeInterval = 0.05, // 50ms minimum between flushes
        maxBufferSize: Int = 10
    ) {
        self.minFlushInterval = minFlushInterval
        self.maxBufferSize = maxBufferSize
    }
    
    public func append(_ token: String) {
        buffer.append(token)
    }
    
    public func shouldFlush() -> Bool {
        let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
        return timeSinceLastFlush >= minFlushInterval || buffer.count >= maxBufferSize
    }
    
    public func flush() -> [String] {
        let tokens = buffer
        buffer.removeAll()
        lastFlushTime = Date()
        return tokens
    }
    
    public func clear() {
        buffer.removeAll()
    }
}

// MARK: - Streaming Buffer

public struct StreamingBuffer {
    private var pendingText: String = ""
    private var flushedText: String = ""
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
        
        // Check if we should flush
        if shouldFlush() {
            return flush()
        }
        
        return nil
    }
    
    public mutating func finish() -> String? {
        guard !pendingText.isEmpty else { return nil }
        let remaining = pendingText
        flushedText.append(remaining)
        pendingText = ""
        return remaining
    }
    
    public mutating func reset() {
        pendingText = ""
        flushedText = ""
    }
    
    private mutating func shouldFlush() -> Bool {
        // Flush if pending is getting too long
        if pendingText.count >= maxPendingLength {
            return true
        }
        
        // Flush if we have a complete sentence and minimum length
        if pendingText.count >= minFlushLength {
            if let lastChar = pendingText.unicodeScalars.last {
                return sentenceDelimiters.contains(lastChar)
            }
        }
        
        // Flush on natural break points
        if pendingText.hasSuffix(" ") && pendingText.count >= minFlushLength {
            // Check if we have a word boundary
            let words = pendingText.split(separator: " ")
            if words.count >= 3 {
                return true
            }
        }
        
        return false
    }
    
    private mutating func flush() -> String {
        let toFlush = pendingText
        flushedText.append(toFlush)
        pendingText = ""
        return toFlush
    }
    
    public var totalLength: Int {
        flushedText.count + pendingText.count
    }
}

// MARK: - Streaming Pipeline

@MainActor
public final class StreamingPipeline: ObservableObject {
    
    // MARK: - Configuration
    
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
    
    // MARK: - Properties
    
    @Published public private(set) var bufferedTokenCount: Int = 0
    @Published public private(set) var totalTokensReceived: Int = 0
    @Published public private(set) var totalTokensFlushed: Int = 0
    
    private var configuration: Configuration
    private var streamingBuffer: StreamingBuffer
    private var tokenBuffer: TokenBuffer?
    private var flushTimer: Timer?
    private var pendingTokens: [String] = []
    private var lastFlushTime: Date = Date()
    
    // MARK: - Initialization
    
    public init(configuration: Configuration = .default) {
        self.configuration = configuration
        self.streamingBuffer = StreamingBuffer(
            minFlushLength: configuration.minFlushLength,
            maxPendingLength: configuration.maxPendingLength
        )
        
        if configuration.enableBuffering {
            self.tokenBuffer = TokenBuffer(
                minFlushInterval: configuration.minFlushInterval,
                maxBufferSize: configuration.maxBufferSize
            )
        }
    }
    
    // MARK: - Public API
    
    /// Ingests a raw token and returns processed tokens ready for display
    public func ingest(_ token: String) -> [String] {
        totalTokensReceived += 1
        
        // Apply jitter reduction if enabled
        if configuration.enableJitterReduction {
            pendingTokens.append(token)
            scheduleJitterFlush()
            return []
        }
        
        // Process through token buffer if enabled
        if let tokenBuffer = tokenBuffer {
            Task {
                await tokenBuffer.append(token)
            }
            
            // Check if we should flush the buffer
            Task {
                if await tokenBuffer.shouldFlush() {
                    let tokens = await tokenBuffer.flush()
                    await MainActor.run {
                        self.flushTokens(tokens)
                    }
                }
            }
            return []
        }
        
        // Direct processing through streaming buffer
        return processToken(token)
    }
    
    /// Finishes the stream and returns any remaining buffered content
    public func finish() -> [String] {
        // Flush any pending jitter reduction tokens
        let jitterTokens = pendingTokens
        pendingTokens.removeAll()
        
        // Flush token buffer
        var bufferTokens: [String] = []
        if let tokenBuffer = tokenBuffer {
            Task {
                bufferTokens = await tokenBuffer.flush()
            }
        }
        
        // Flush streaming buffer
        if let finalText = streamingBuffer.finish() {
            totalTokensFlushed += 1
            return jitterTokens + bufferTokens + [finalText]
        }
        
        return jitterTokens + bufferTokens
    }
    
    /// Resets the pipeline state
    public func reset() {
        streamingBuffer.reset()
        pendingTokens.removeAll()
        
        if let tokenBuffer = tokenBuffer {
            Task {
                await tokenBuffer.clear()
            }
        }
        
        flushTimer?.invalidate()
        flushTimer = nil
        
        bufferedTokenCount = 0
        totalTokensReceived = 0
        totalTokensFlushed = 0
    }
    
    /// Updates the configuration
    public func updateConfiguration(_ newConfiguration: Configuration) {
        self.configuration = newConfiguration
        self.streamingBuffer = StreamingBuffer(
            minFlushLength: newConfiguration.minFlushLength,
            maxPendingLength: newConfiguration.maxPendingLength
        )
        
        if newConfiguration.enableBuffering {
            self.tokenBuffer = TokenBuffer(
                minFlushInterval: newConfiguration.minFlushInterval,
                maxBufferSize: newConfiguration.maxBufferSize
            )
        } else {
            self.tokenBuffer = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func scheduleJitterFlush() {
        flushTimer?.invalidate()
        
        flushTimer = Timer.scheduledTimer(withTimeInterval: configuration.jitterReductionDelay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            let tokens = self.pendingTokens
            self.pendingTokens.removeAll()
            
            for token in tokens {
                let processed = self.processToken(token)
                // These tokens are now ready - would be yielded in async context
            }
        }
    }
    
    private func processToken(_ token: String) -> [String] {
        var results: [String] = []
        
        // Process through streaming buffer
        if let flushedText = streamingBuffer.ingest(token) {
            results.append(flushedText)
            totalTokensFlushed += 1
        }
        
        return results
    }
    
    private func flushTokens(_ tokens: [String]) {
        for token in tokens {
            let processed = processToken(token)
            // Processed tokens are ready for display
        }
        bufferedTokenCount = 0
    }
    
    // MARK: - Stream Coordinator
    
    /// Coordinates streaming with UI updates for smooth scrolling
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

// MARK: - Stream Coordinator

@MainActor
public final class StreamCoordinator {
    private let pipeline: StreamingPipeline
    private let onToken: (String) -> Void
    private let onComplete: () -> Void
    private var accumulatedText: String = ""
    private var displayTimer: Timer?
    private let displayInterval: TimeInterval = 0.016 // ~60fps
    
    public init(
        pipeline: StreamingPipeline,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.pipeline = pipeline
        self.onToken = onToken
        self.onComplete = onComplete
    }
    
    public func start() {
        displayTimer = Timer.scheduledTimer(withTimeInterval: displayInterval, repeats: true) { [weak self] _ in
            self?.processPendingDisplay()
        }
    }
    
    public func ingest(_ token: String) {
        let processed = pipeline.ingest(token)
        for text in processed {
            accumulatedText.append(text)
        }
    }
    
    public func finish() {
        displayTimer?.invalidate()
        
        // Flush any remaining content
        let finalTokens = pipeline.finish()
        for token in finalTokens {
            accumulatedText.append(token)
        }
        
        // Send final accumulated text
        if !accumulatedText.isEmpty {
            onToken(accumulatedText)
        }
        
        onComplete()
    }
    
    public func cancel() {
        displayTimer?.invalidate()
        pipeline.reset()
    }
    
    private func processPendingDisplay() {
        // This would coordinate with the UI for smooth updates
        // For now, we just pass through
    }
}

// MARK: - Async Stream Extension

extension StreamingPipeline {
    /// Creates an async stream that yields processed tokens
    public func createAsyncStream(
        from source: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await token in source {
                        let processed = self.ingest(token)
                        for text in processed {
                            continuation.yield(text)
                        }
                    }
                    
                    // Flush remaining tokens
                    let finalTokens = self.finish()
                    for token in finalTokens {
                        continuation.yield(token)
                    }
                    
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}