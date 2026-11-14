import Foundation

enum ScreenNavigation {
    struct Line {
        let text: String
        let x: Double
        let y: Double // top-origin normalized frame coordinates
        let width: Double
        let height: Double
    }
    struct Reading {
        let instruction: String
        let distance: String
        let turn: PineNavigationWire.Turn
        let distanceLine: Line
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "đ", with: "d").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parse(_ lines: [Line], arrow: PineNavigationWire.Turn? = nil) -> Reading? {
        let bottom = lines.filter { $0.y > 0.5 }.map { normalized($0.text) }
        // A navigation banner plus the Maps watermark/exit control and remaining
        // duration is required. Arbitrary text from another app isn't guidance.
        guard bottom.contains(where: { $0.contains("google") || $0 == "thoat" || $0 == "exit" }),
              bottom.contains(where: { $0.range(of: #"\d+\s*(phut|min|gio|hr|hour)"#, options: .regularExpression) != nil }) else { return nil }
        let candidates = lines.filter {
            $0.y > 0.025 && $0.y < 0.34 && $0.height > 0.009 &&
            normalized($0.text).range(of: #"^(in\s+)?\d+([.,]\d+)?\s*(km|m)$"#, options: .regularExpression) != nil
        }
        guard let distance = candidates.max(by: { $0.height < $1.height }) else { return nil }
        let streetLines = lines.filter {
            $0.x > 0.15 && $0.y > distance.y - 0.035 && $0.y < min(0.36, distance.y + 0.13) &&
            $0.text != distance.text && $0.height > 0.01 && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.sorted { $0.y < $1.y }
        guard !streetLines.isEmpty else { return nil }
        let text = String(streetLines.prefix(2).map(\.text).joined(separator: " ").prefix(140))
        let textTurn = RouteInstruction.turn(for: text)
        let turn = textTurn == .unspecified ? (arrow ?? .unspecified) : textTurn
        let instruction = textTurn == .unspecified ? (turn == .unspecified ? "Xem Google Maps: " : turn.title + " · ") + text : text
        return Reading(instruction: instruction, distance: String(distance.text.prefix(24)), turn: turn, distanceLine: distance)
    }
}

// Small independent geometric templates. Only strong, well-separated matches
// produce an arrow; uncertain shapes keep a generic icon and the OCR text.
enum NavigationArrow {
    struct Match { let turn: PineNavigationWire.Turn; let confidence: Double }
    static let size = 32

    static func template(_ turn: PineNavigationWire.Turn) -> [Bool] {
        var mask = [Bool](repeating: false, count: size * size)
        let paths: [[(Double, Double)]]
        switch turn {
        case .left: paths = [[(24,29),(24,16),(21,11),(6,11)],[(12,4),(5,11),(12,18)]]
        case .right: return mirror(template(.left))
        case .straight: paths = [[(16,29),(16,5)],[(7,13),(16,4),(25,13)]]
        case .uTurn: paths = [[(25,29),(25,11),(22,5),(13,3),(6,7),(5,23)],[(0,17),(5,24),(12,18)]]
        default: return mask
        }
        for path in paths {
            for (a,b) in zip(path,path.dropFirst()) {
                let dx = b.0-a.0, dy = b.1-a.1
                for y in 0..<size { for x in 0..<size {
                    let t = max(0,min(1,((Double(x)-a.0)*dx+(Double(y)-a.1)*dy)/(dx*dx+dy*dy)))
                    if hypot(Double(x)-a.0-t*dx,Double(y)-a.1-t*dy) < 2.7 { mask[y*size+x] = true }
                } }
            }
        }
        return mask
    }

    private static func mirror(_ mask: [Bool]) -> [Bool] {
        (0..<size*size).map { mask[($0/size)*size + size-1-$0%size] }
    }

    private static func fit(_ mask: [Bool]) -> [Bool] {
        let positions = mask.indices.filter { mask[$0] }
        guard let minX = positions.map({ $0%size }).min(), let maxX = positions.map({ $0%size }).max(),
              let minY = positions.map({ $0/size }).min(), let maxY = positions.map({ $0/size }).max(),
              maxX > minX, maxY > minY else { return mask }
        var result = [Bool](repeating: false, count: size*size)
        for y in 2...29 { for x in 2...29 {
            let sourceX = minX+(x-2)*(maxX-minX)/27
            let sourceY = minY+(y-2)*(maxY-minY)/27
            result[y*size+x] = mask[sourceY*size+sourceX]
        } }
        return result
    }

    static func classify(_ input: [Bool]) -> Match? {
        guard input.count == size*size else { return nil }
        let mask = fit(input)
        let filled = mask.filter { $0 }.count
        guard filled > 100, filled < 700 else { return nil }
        let ranked = [PineNavigationWire.Turn.left, .right, .straight, .uTurn].map { turn -> Match in
            let expected = fit(template(turn))
            var intersection = 0, union = 0
            for index in mask.indices {
                if mask[index] && expected[index] { intersection += 1 }
                if mask[index] || expected[index] { union += 1 }
            }
            return Match(turn: turn, confidence: Double(intersection)/Double(max(1,union)))
        }.sorted { $0.confidence > $1.confidence }
        guard ranked[0].confidence >= 0.58, ranked[0].confidence - ranked[1].confidence > 0.10 else { return nil }
        return ranked[0]
    }
}
