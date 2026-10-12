import Foundation

/// Dünne Hülle um NSLocalizedString. Die Texte liegen unter Resources/<lang>.lproj/
/// (Localizable.strings, Mehrzahlformen in Localizable.stringsdict); die Sprache
/// folgt der macOS-Einstellung, Entwicklungssprache ist Englisch.
enum L10n {
    /// Übersetzter Text zum semantischen Schlüssel.
    static func tr(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }

    /// Übersetztes Format mit Platzhaltern (%@, %ld). Mehrzahlregeln aus der
    /// .stringsdict greifen automatisch.
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: NSLocalizedString(key, comment: ""), locale: locale, arguments: args)
    }

    /// Locale der tatsächlich verwendeten App-Sprache – nicht zwingend die Region
    /// des Systems. Damit passen Datums- und Zeitangaben zur Sprache der Oberfläche.
    /// Die Region des Systems bleibt erhalten, sofern die Sprache keine eigene mitbringt.
    static let locale: Locale = {
        let language = Bundle.main.preferredLocalizations.first ?? "en"
        if !language.contains("-"), let region = Locale.current.region?.identifier {
            return Locale(identifier: "\(language)_\(region)")
        }
        return Locale(identifier: language)
    }()
}
