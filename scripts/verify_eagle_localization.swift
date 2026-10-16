import Foundation

@main struct LocalizationChecks {
    @MainActor static func main() {
        let defaults = UserDefaults.standard
        let savedArguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(savedArguments, forName: UserDefaults.argumentDomain) }
        let key = EagleLanguage.storageKey
        precondition(key == "lara.interfaceLanguage" && key == LaraLanguage.storageKey)
        precondition(key == PublicLanguage.storageKey)
        precondition(defaults.object(forKey: key) == nil, "Fixture requires an isolated preference domain")
        let persistentBefore = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier!)
        let hasResources = CommandLine.arguments[1] == "resources"
        precondition((Bundle.main.path(forResource: "en", ofType: "lproj") != nil) == hasResources)

        // The public English and Spanish stay first and unchanged; Simplified Chinese was added after them.
        precondition(EagleLanguage.allCases.map(\.rawValue) == ["en", "es", "zh-Hans"])
        precondition(Array(EagleLanguage.allCases.prefix(2)).map(\.rawValue) == PublicLanguage.allCases.map(\.rawValue))
        precondition(EagleLanguage.chinese.displayName == "简体中文" && EagleLanguage.chinese.shortName == "中文")
        for (index, language) in EagleLanguage.allCases.prefix(2).enumerated() {
            let reference = PublicLanguage.allCases[index]
            let legacy: LaraLanguage = language
            precondition(legacy == language && legacy.id == reference.id)
            precondition(language.locale.identifier == reference.locale.identifier)
            precondition(language.displayName == ["English", "Español"][index])
            precondition(language.displayName == reference.displayName)
            precondition(language.shortName == ["EN", "ES"][index])
            precondition(language.shortName == reference.shortName)
        }

        // Reuse one captured production callback across changes: no cached language.
        let message = GalleryMessage.failure
        let cases: [(Any?, EagleLanguage)] = [
            (nil, .english), ("en", .english), ("es", .spanish),
            ("", .english), ("ES", .english), ("es-MX", .english),
            ("fr", .english), (42, .english), (["es"], .english),
            ("es", .spanish), ("en", .english), ("es", .spanish), (nil, .english),
        ]
        for (raw, expected) in cases {
            var arguments = savedArguments
            if let raw { arguments[key] = raw } else { arguments.removeValue(forKey: key) }
            defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
            precondition(EagleLocalization.language == expected)
            precondition(LaraL10n.language == expected)
            precondition(EagleLocalization.language.rawValue == PublicLocalization.language.rawValue)
            for (english, spanish) in [("Ready", "Listo"), ("", ""), ("Eagle ✓", "Águila ✓")] {
                let result = EagleLocalization.text(en: english, es: spanish)
                precondition(result == (expected == .spanish ? spanish : english))
                precondition(result == LaraL10n.text(en: english, es: spanish))
                precondition(result == PublicLocalization.text(en: english, es: spanish))
            }
            let failure = expected == .spanish
                ? "No se pudo cargar la colección en línea."
                : "The online collection could not be loaded."
            precondition(message() == failure, "Gallery callback captured an obsolete language")
            for resourceKey in ["Original key", "Missing key", ""] {
                let translated = expected == .english && hasResources && resourceKey == "Original key"
                    ? "Translated ✓" : resourceKey
                let result = EagleLocalization.localized(resourceKey)
                precondition(result == translated)
                precondition(result == LaraL10n.localized(resourceKey))
                precondition(result == PublicLocalization.localized(resourceKey))
            }
        }
        let persistentAfter = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier!)
        precondition((persistentBefore as NSDictionary?) == (persistentAfter as NSDictionary?))
        print("PASS: \(cases.count) preference/change cases, language metadata, live Gallery callback, aliases and \(hasResources ? "resource lookup" : "missing-bundle fallback")")
    }
}
