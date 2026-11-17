import Foundation

// In-app language (Vietnamese / English / Turkish), chosen from the globe menu on the main screen.
// On iPhone the app defaults to Vietnamese; on macOS unit-test hosts it follows the host locale unless overridden.
enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese = "vi"
    case english = "en"
    case turkish = "tr"

    static let storageKey = "appLanguage"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vietnamese: return "Tiếng Việt"
        case .english: return "English"
        case .turkish: return "Türkçe"
        }
    }

    static var current: AppLanguage {
        if let saved = UserDefaults.standard.string(forKey: storageKey), let language = AppLanguage(rawValue: saved) {
            return language
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("tr") { return .turkish }
        if preferred.hasPrefix("vi") { return .vietnamese }
        #if os(iOS)
        return .vietnamese
        #else
        return .english
        #endif
    }
}

/// Picks the Vietnamese, English or Turkish text according to the in-app language.
func L(_ english: String, _ turkish: String, vi vietnamese: String? = nil) -> String {
    switch AppLanguage.current {
    case .vietnamese: return vietnamese ?? english
    case .turkish: return turkish
    case .english: return english
    }
}

enum AppInfo {
    // CFBundleDisplayName, so a fork or a private build can carry its own name
    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "HuaSideload"
    }
}
