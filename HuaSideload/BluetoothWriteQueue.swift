import Foundation

// One ATT write at a time when acknowledgements are required. Without-response
// writes advance only while CoreBluetooth advertises capacity. Never interleave
// raw fragments belonging to different Huawei protocol frames.
struct BluetoothWriteQueue {
    private var chunks: [[UInt8]] = []
    private var offset = 0
    private(set) var awaitingResponse = false

    var hasPending: Bool { offset < chunks.count || awaitingResponse }

    @discardableResult
    mutating func enqueue(_ frame: [UInt8], limit: Int) -> Bool {
        guard limit > 0, !frame.isEmpty else { return false }
        var start = 0
        while start < frame.count {
            let end = start + min(limit, frame.count - start)
            chunks.append(Array(frame[start..<end]))
            start = end
        }
        return true
    }

    mutating func next(withResponse: Bool, canSendWithoutResponse: Bool) -> [UInt8]? {
        guard !awaitingResponse, offset < chunks.count,
              withResponse || canSendWithoutResponse else { return nil }
        let chunk = chunks[offset]
        offset += 1
        awaitingResponse = withResponse
        if offset == chunks.count { chunks.removeAll(keepingCapacity: true); offset = 0 }
        return chunk
    }

    @discardableResult
    mutating func acknowledge() -> Bool {
        guard awaitingResponse else { return false }
        awaitingResponse = false
        return true
    }

    mutating func reset() {
        chunks.removeAll(keepingCapacity: true)
        offset = 0
        awaitingResponse = false
    }
}

// A cancelled command must not clear a new command's busy state, or publish a
// result after Disconnect/reconnect. Used by every WatchLink foreground command.
struct WatchCommandState {
    struct Ticket: Equatable {
        fileprivate let connection: UUID
        fileprivate let operation: UUID
    }
    private var connection = UUID()
    private var active: Ticket?

    mutating func begin() -> Ticket? {
        guard active == nil else { return nil }
        let ticket = Ticket(connection: connection, operation: UUID())
        active = ticket
        return ticket
    }

    func accepts(_ ticket: Ticket) -> Bool { active == ticket && ticket.connection == connection }

    @discardableResult
    mutating func finish(_ ticket: Ticket) -> Bool {
        guard accepts(ticket) else { return false }
        active = nil
        return true
    }

    mutating func reset() { connection = UUID(); active = nil }
}
