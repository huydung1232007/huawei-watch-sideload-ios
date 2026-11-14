import XCTest
@testable import HuaSideloadParsing

final class RouteInstructionTests: XCTestCase {
    func testEnglishAndVietnameseManeuvers() {
        XCTAssertEqual(RouteInstruction.turn(for: "Turn left onto Main Street"), .left)
        XCTAssertEqual(RouteInstruction.turn(for: "Rẽ phải vào đường A"), .right)
        XCTAssertEqual(RouteInstruction.turn(for: "Quay đầu"), .uTurn)
        XCTAssertEqual(RouteInstruction.turn(for: "Continue onto Left Bank Road"), .straight)
    }

    func testRoadNamesDoNotInventTurns() {
        XCTAssertEqual(RouteInstruction.turn(for: "Left Bank Road"), .unspecified)
        XCTAssertEqual(RouteInstruction.turn(for: "Head north on Right Street"), .straight)
        XCTAssertEqual(RouteInstruction.turn(for: "Continue onto đường Trái"), .straight)
    }

    func testRoundaboutsAndUnsupportedLanguagesRemainUnspecified() {
        XCTAssertEqual(RouteInstruction.turn(for: "At the roundabout take the left exit"), .unspecified)
        XCTAssertEqual(RouteInstruction.turn(for: "Vào vòng xuyến rồi rẽ phải"), .unspecified)
        XCTAssertEqual(RouteInstruction.turn(for: "Tournez à gauche"), .unspecified)
    }
}
