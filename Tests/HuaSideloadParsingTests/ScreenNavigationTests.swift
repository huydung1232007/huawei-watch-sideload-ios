import XCTest
@testable import HuaSideloadParsing

final class ScreenNavigationTests: XCTestCase {
    private func line(_ text: String, x: Double = 0.25, y: Double, height: Double = 0.03) -> ScreenNavigation.Line {
        .init(text: text, x: x, y: y, width: 0.6, height: height)
    }
    private var banner: [ScreenNavigation.Line] {
        [line("100 m", y: 0.09), line("Đường Lê Lợi", y: 0.14), line("12 phút", y: 0.85), line("Thoát", y: 0.92)]
    }

    func testStreetAndDistanceWithExplicitlyRecognizedArrow() throws {
        let result = try XCTUnwrap(ScreenNavigation.parse(banner, arrow: .left))
        XCTAssertEqual(result.distance, "100 m")
        XCTAssertEqual(result.turn, .left)
        XCTAssertTrue(result.instruction.hasPrefix("Rẽ trái"))
    }

    func testTextWithoutReliableArrowDoesNotInventDirection() throws {
        let result = try XCTUnwrap(ScreenNavigation.parse(banner))
        XCTAssertEqual(result.turn, .unspecified)
        XCTAssertTrue(result.instruction.hasPrefix("Xem Google Maps:"))
    }

    func testUnrelatedAppAndSearchScreenDoNotProduceGuidance() {
        XCTAssertNil(ScreenNavigation.parse([line("100 m", y: 0.09), line("Tin nhắn", y: 0.14)]))
        XCTAssertNil(ScreenNavigation.parse([line("100 m", y: 0.5), line("Google", y: 0.8), line("12 phút", y: 0.85)]))
        XCTAssertNil(ScreenNavigation.parse([line("Thông báo sau 100 m", y: 0.09)] + Array(banner.dropFirst())))
    }

    func testEnglishNavigationAndTextualDirection() throws {
        let lines = [line("1.2 km", y: 0.09), line("Turn right onto Main Street", y: 0.14), line("10 min", y: 0.86), line("Google", y: 0.8)]
        XCTAssertEqual(try XCTUnwrap(ScreenNavigation.parse(lines)).turn, .right)
    }

    func testOwnGeometricTemplatesAreSeparated() throws {
        for turn in [PineNavigationWire.Turn.left, .right, .straight, .uTurn] {
            XCTAssertEqual(try XCTUnwrap(NavigationArrow.classify(NavigationArrow.template(turn))).turn, turn)
        }
    }

    func testEmptyOrFilledImageCannotBecomeTurnArrow() {
        XCTAssertNil(NavigationArrow.classify([Bool](repeating: false, count: 1024)))
        XCTAssertNil(NavigationArrow.classify([Bool](repeating: true, count: 1024)))
        XCTAssertNil(NavigationArrow.classify([]))
    }
}
