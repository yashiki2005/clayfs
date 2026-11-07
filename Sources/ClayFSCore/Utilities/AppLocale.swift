import Foundation

public enum AppLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case japanese = "ja"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case korean = "ko"

    public static func detect(
        cliArgs: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        // 1. Explicit CLI arguments (--lang=xx, --lang xx, --ja, --en, --zh, --es, etc.)
        for (i, arg) in cliArgs.enumerated() {
            if arg == "--lang" && i + 1 < cliArgs.count {
                if let match = from(code: cliArgs[i + 1]) { return match }
            }
            if arg.starts(with: "--lang=") {
                let code = String(arg.dropFirst(7))
                if let match = from(code: code) { return match }
            }
            if arg == "--en" || arg == "-en" { return .english }
            if arg == "--ja" || arg == "-ja" { return .japanese }
            if arg == "--zh" || arg == "-zh" || arg == "--cn" { return .simplifiedChinese }
            if arg == "--zh-hant" || arg == "--tw" { return .traditionalChinese }
            if arg == "--es" || arg == "-es" { return .spanish }
            if arg == "--fr" || arg == "-fr" { return .french }
            if arg == "--de" || arg == "-de" { return .german }
            if arg == "--ko" || arg == "-ko" { return .korean }
        }

        // 2. POSIX environment variables (LC_ALL, LC_MESSAGES, LANG)
        let envLang = environment["LC_ALL"] ?? environment["LC_MESSAGES"] ?? environment["LANG"] ?? ""
        if !envLang.isEmpty && envLang != "C" && envLang != "POSIX" {
            if let match = from(code: envLang) {
                return match
            }
        }

        // 3. System Preferred Languages (macOS Language & Region setting)
        for pref in preferredLanguages {
            if let match = from(code: pref) {
                return match
            }
        }

        // 4. Current locale fallback
        if let currentCode = Locale.current.language.languageCode?.identifier {
            if let match = from(code: currentCode) {
                return match
            }
        }

        return .english
    }

    private static func from(code: String) -> AppLanguage? {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        if lower.starts(with: "zh-hant") || lower.starts(with: "zh-tw") || lower.starts(with: "zh-hk") {
            return .traditionalChinese
        }
        if lower.starts(with: "zh") {
            return .simplifiedChinese
        }
        if lower.starts(with: "ja") {
            return .japanese
        }
        if lower.starts(with: "ko") {
            return .korean
        }
        if lower.starts(with: "es") {
            return .spanish
        }
        if lower.starts(with: "fr") {
            return .french
        }
        if lower.starts(with: "de") {
            return .german
        }
        if lower.starts(with: "en") {
            return .english
        }
        return nil
    }
}
