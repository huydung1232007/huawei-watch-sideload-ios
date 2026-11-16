import Foundation
import Network

// A fresh, short-lived local TCP connection for each signed request. No retry
// of a media toggle after an uncertain reply: a retry could toggle it twice.
final class PCRemoteTransaction: @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "HuaSideload.PCRemote")
    private let frame: Data
    private var continuation: CheckedContinuation<Data, Error>?
    private var finished = false
    private var timeout: DispatchWorkItem?

    init(configuration: PCRemoteConfiguration, frame: Data) {
        self.frame = frame
        connection = NWConnection(host: NWEndpoint.Host(configuration.host),
                                  port: NWEndpoint.Port(rawValue: UInt16(configuration.port))!, using: .tcp)
    }
    func run() async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    guard !self.finished else { continuation.resume(throwing: CancellationError()); return }
                    self.continuation = continuation
                    let timeout = DispatchWorkItem { self.finish(.failure(PCRemoteError.timeout)) }
                    self.timeout = timeout
                    self.queue.asyncAfter(deadline: .now() + 6, execute: timeout)
                    self.connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready: self.send()
                        case .failed: self.finish(.failure(PCRemoteError.unavailable))
                        case .cancelled: self.finish(.failure(CancellationError()))
                        default: break
                        }
                    }
                    self.connection.start(queue: self.queue)
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }
    private func send() {
        connection.send(content: frame, completion: .contentProcessed { error in
            guard !self.finished else { return }
            guard error == nil else { self.finish(.failure(PCRemoteError.unavailable)); return }
            self.read(4) { header in
                do {
                    let count = try PCRemoteWire.frameLength(header)
                    self.read(count) { self.finish(.success($0)) }
                } catch { self.finish(.failure(error)) }
            }
        })
    }
    private func read(_ count: Int, accumulated: Data = Data(), then: @escaping (Data) -> Void) {
        guard !finished else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: count - accumulated.count) { data, _, complete, error in
            guard !self.finished else { return }
            var result = accumulated
            if let data { result.append(data) }
            if result.count == count { then(result) }
            else if error != nil || complete { self.finish(.failure(PCRemoteError.unavailable)) }
            else { self.read(count, accumulated: result, then: then) }
        }
    }
    private func finish(_ result: Result<Data, Error>) {
        guard !finished else { return }
        finished = true
        timeout?.cancel(); timeout = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        let current = continuation; continuation = nil
        current?.resume(with: result)
    }
}

@MainActor
final class PCRemoteTransport {
    private var transaction: PCRemoteTransaction?
    func cancel() { transaction?.cancel(); transaction = nil }
    func send(_ command: PCRemoteCommand, configuration: PCRemoteConfiguration) async throws {
        try Task.checkCancellation()
        let request = try PCRemoteWire.request(command, configuration: configuration)
        let current = PCRemoteTransaction(configuration: configuration, frame: try PCRemoteWire.frame(request))
        transaction = current
        defer { if transaction === current { transaction = nil } }
        let reply = try await current.run()
        try Task.checkCancellation()
        _ = try PCRemoteWire.verifyReply(reply, requestID: request.id, key: configuration.keyBytes!)
    }
}
