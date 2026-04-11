import Foundation

@MainActor
public protocol ExecutionRuntime: AnyObject {
    func prepareIfNeeded(tuning: JarvisGenerationTuning?) async throws
    func streamResponse(request: JarvisAssistantRequest) -> AsyncThrowingStream<String, Error>
    func cancel()
    var lastGenerationStopReason: JarvisRuntimeGenerationStopReason? { get }
}

@MainActor
public final class JarvisLocalExecutionRuntimeAdapter: ExecutionRuntime {
    private let runtime: JarvisLocalModelRuntime

    public init(runtime: JarvisLocalModelRuntime) {
        self.runtime = runtime
    }

    public func prepareIfNeeded(tuning: JarvisGenerationTuning?) async throws {
        try await runtime.prepareIfNeeded(tuning: tuning)
    }

    public func streamResponse(request: JarvisAssistantRequest) -> AsyncThrowingStream<String, Error> {
        runtime.streamResponse(request: request)
    }

    public func cancel() {
        runtime.cancel()
    }

    public var lastGenerationStopReason: JarvisRuntimeGenerationStopReason? {
        runtime.lastGenerationDiagnostics?.stopReason
    }
}
