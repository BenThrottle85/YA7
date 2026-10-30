import Foundation

enum L10n {
    static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        return .module
        #else
        return .main
        #endif
    }

    static func text(_ key: String, bundle: Bundle = resourceBundle) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, _ arguments: Any...) -> String {
        formatted(key, arguments: arguments, bundle: resourceBundle)
    }

    static func formatted(_ key: String, arguments: [Any], bundle: Bundle) -> String {
        let values: [CVarArg] = arguments.map { String(describing: $0) }
        return String(format: text(key, bundle: bundle), locale: Locale.current, arguments: values)
    }

    static func itemCount(_ count: Int) -> String {
        format(count == 1 ? "%@ item" : "%@ items", count)
    }

    static func selectedItemCount(_ count: Int) -> String {
        format(count == 1 ? "%@ selected item" : "%@ selected items", count)
    }
}
