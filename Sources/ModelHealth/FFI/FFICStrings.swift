import Foundation

/// Runs `body` with a C string pointer for `value`, or a null pointer when it's absent.
///
/// `String.withCString` has no optional form, and switching over the optional at each call
/// site stops scaling once a function takes more than one or two nullable strings.
internal func withOptionalCString<R>(
    _ value: String?,
    _ body: (UnsafePointer<CChar>?) -> R
) -> R {
    guard let value else {
        return body(nil)
    }
    return value.withCString { body($0) }
}
