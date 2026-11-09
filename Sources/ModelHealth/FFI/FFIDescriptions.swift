import Foundation
import ModelHealthFFI


extension Subject: CustomStringConvertible {
    public var description: String {
        name.withCString { takingString(model_health_describe_subject(Int32(id), $0)) }
    }
}

extension Session: CustomStringConvertible {
    public var description: String {
        id.withCString { idPtr in
            name.withCString { namePtr in
                takingString(model_health_describe_session(idPtr, namePtr))
            }
        }
    }
}

extension Activity: CustomStringConvertible {
    public var description: String {
        id.withCString { idPtr in
            withOptionalCString(name) { namePtr in
                takingString(model_health_describe_activity(idPtr, namePtr))
            }
        }
    }
}

/// What a record says when it has no client to read through.
internal func notAttached(_ typeName: String) -> ModelHealthError {
    .notAttached(typeName.withCString { takingString(model_health_not_attached_message($0)) })
}

/// Takes over a string the C layer allocated, and frees it.
private func takingString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    defer { model_health_free_string(pointer) }
    return String(cString: pointer)
}
