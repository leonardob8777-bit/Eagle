import Foundation

nonisolated enum EagleLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case spanish = "es"
    case chinese = "zh-Hans"

    static let storageKey = "lara.interfaceLanguage"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .chinese: return "简体中文"
        }
    }

    var shortName: String {
        switch self {
        case .english: return "EN"
        case .spanish: return "ES"
        case .chinese: return "中文"
        }
    }
}

nonisolated enum EagleLocalization {
    static var language: EagleLanguage {
        guard
            let rawValue = UserDefaults.standard.string(forKey: EagleLanguage.storageKey),
            let language = EagleLanguage(rawValue: rawValue)
        else {
            return .english
        }
        return language
    }

    /// Chinese text for an English string, installed by the app at launch (the table lives outside
    /// the core module). Until then, Chinese falls back to English.
    nonisolated(unsafe) static var chineseText: (String) -> String = { $0 }

    static func text(en: String, es: String) -> String {
        switch language {
        case .spanish: return es
        case .chinese: return chineseText(en)
        case .english: return en
        }
    }

    static func localized(_ key: String) -> String {
        if language == .spanish {
            return key
        }
        guard
            let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}
