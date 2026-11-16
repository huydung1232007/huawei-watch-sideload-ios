import XCTest
@testable import HuaSideloadParsing

final class BluetoothWriteQueueTests: XCTestCase {
    func testWithResponseWaitsForEachAckAndPreservesFrameOrder() {
        var queue = BluetoothWriteQueue()
        XCTAssertTrue(queue.enqueue([1, 2, 3, 4, 5], limit: 2))
        XCTAssertTrue(queue.enqueue([6, 7], limit: 2))
        let expectedChunks: [[UInt8]] = [[1, 2], [3, 4], [5], [6, 7]]
        for expected in expectedChunks {
            XCTAssertEqual(queue.next(withResponse: true, canSendWithoutResponse: false), expected)
            XCTAssertTrue(queue.hasPending)
            XCTAssertNil(queue.next(withResponse: true, canSendWithoutResponse: true))
            XCTAssertTrue(queue.acknowledge())
        }
        XCTAssertFalse(queue.hasPending)
        XCTAssertFalse(queue.acknowledge())
    }

    func testWithoutResponseBackpressureDoesNotDropChunk() {
        var queue = BluetoothWriteQueue()
        queue.enqueue([1, 2, 3], limit: 2)
        XCTAssertNil(queue.next(withResponse: false, canSendWithoutResponse: false))
        XCTAssertEqual(queue.next(withResponse: false, canSendWithoutResponse: true), [1, 2])
        XCTAssertNil(queue.next(withResponse: false, canSendWithoutResponse: false))
        XCTAssertEqual(queue.next(withResponse: false, canSendWithoutResponse: true), [3])
        XCTAssertFalse(queue.hasPending)
    }

    func testDisconnectDiscardsUnsentFragmentsAndInflightAck() {
        var queue = BluetoothWriteQueue()
        queue.enqueue([1, 2, 3], limit: 1)
        _ = queue.next(withResponse: true, canSendWithoutResponse: true)
        queue.reset()
        XCTAssertFalse(queue.hasPending)
        XCTAssertFalse(queue.acknowledge())
        queue.enqueue([9], limit: 20)
        XCTAssertEqual(queue.next(withResponse: true, canSendWithoutResponse: true), [9])
    }

    func testRejectsEmptyAndInvalidATTLimit() {
        var queue = BluetoothWriteQueue()
        XCTAssertFalse(queue.enqueue([], limit: 20))
        XCTAssertFalse(queue.enqueue([1], limit: 0))
        XCTAssertFalse(queue.enqueue([1], limit: -1))
        XCTAssertFalse(queue.hasPending)
    }

    func testDuplicatePairCannotStartAndOldTaskCannotFinishNewCommand() throws {
        var state = WatchCommandState()
        let old = try XCTUnwrap(state.begin())
        XCTAssertNil(state.begin())
        state.reset()
        let new = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.accepts(old))
        XCTAssertFalse(state.finish(old))
        XCTAssertTrue(state.accepts(new))
        XCTAssertTrue(state.finish(new))
        XCTAssertNotNil(state.begin())
    }
}
