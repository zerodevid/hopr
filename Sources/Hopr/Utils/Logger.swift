import Foundation

enum Log {
    static var enabled = true

    static func info(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        print("[Hopr] \(message())")
        fflush(stdout)
    }

    static func error(_ message: @autoclosure () -> String) {
        print("[Hopr ERROR] \(message())")
        fflush(stdout)
    }

    static func debug(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Hopr DEBUG] \(message())")
        fflush(stdout)
        #endif
    }
}
