import Foundation

// Independent first-install probe for our own Lite Wearable app. All displayed
// route values are marked as sample data; it does not consume live navigation.
enum NavMiniWire {
    static let watchPackage = "com.huydung1232007.navmini"
    // Stable protocol address: Sideloadly may change the iOS bundle identifier.
    static let phonePackage = "com.huydung1232007.navmini.phone"

    private struct Request: Decodable { let t: String; let v: Int; let n: Int }
    static func nonce(in message: [String: Any],type: String) -> Int? {
        guard JSONSerialization.isValidJSONObject(message),
              let bytes = try? JSONSerialization.data(withJSONObject:message),bytes.count <= 1000,
              let request = try? JSONDecoder().decode(Request.self,from:bytes),
              request.t == type,request.v == 1,(1...999_999_999).contains(request.n) else { return nil }
        return request.n
    }
    static func reply(to message: [String: Any],at time: Date) -> [String: Any]? {
        guard let nonce = nonce(in:message,type:"navmini.hello") else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return ["t":"navmini.status","v":1,"n":nonce,"demo":true,
                "instruction":"RE TRAI - DU LIEU THU","distance":"120 m","turn":"left",
                "remaining":"3.2 km","duration":"9 phut","eta":"18:45","speed":"32 km/h",
                "phoneTime":formatter.string(from:time)]
    }
}
