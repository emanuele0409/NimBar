// SPDX-License-Identifier: GPL-3.0-only
import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en", italian = "it"
    var id: String { rawValue }
    var title: String { self == .english ? "English" : "Italiano" }
    var locale: Locale { Locale(identifier: rawValue) }
}

enum L10n {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var selected: AppLanguage = .english
    static var language: AppLanguage {
        get { lock.lock(); defer { lock.unlock() }; return selected }
        set { lock.lock(); selected = newValue; lock.unlock() }
    }
    static var locale: Locale { language.locale }
    static func bundle(for language: AppLanguage) -> Bundle {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    static func text(_ key: String, language: AppLanguage? = nil) -> String {
        bundle(for: language ?? self.language).localizedString(forKey: key, value: key, table: "Localizable")
    }
    static func format(_ key: String, _ arguments: String...) -> String {
        format(key, arguments: arguments)
    }
    static func format(_ key: String, arguments: [String], language: AppLanguage? = nil) -> String {
        let language = language ?? self.language
        return String(format: text(key, language: language), locale: language.locale,
                      arguments: arguments.map { $0 as CVarArg })
    }
    static func errorDescription(_ error: NSError, language: AppLanguage? = nil) -> String {
        guard error.domain == "NimBar.MenuBarNativeHider" else { return error.localizedDescription }
        let key: String
        switch error.code {
        case 1: key = "L’API nativa per nascondere le icone non è disponibile su questa versione di macOS."
        case 2: key = "La richiesta macOS è scaduta; le icone sono state ripristinate."
        default: key = "L’API nativa ha rifiutato la richiesta."
        }
        return text(key, language: language)
    }
}

struct LocalizedMessage {
    enum Argument {
        case text(String), number(Int), error(NSError)
        func render(language: AppLanguage) -> String {
            switch self {
            case .text(let value): value
            case .number(let value): value.formatted(.number.locale(language.locale))
            case .error(let value): L10n.errorDescription(value, language: language)
            }
        }
    }
    let key: String
    var arguments: [Argument] = []
    init(_ key: String, _ arguments: [Argument] = []) { self.key = key; self.arguments = arguments }
    var text: String {
        let language = L10n.language
        return L10n.format(key, arguments: arguments.map { $0.render(language: language) }, language: language)
    }
}
