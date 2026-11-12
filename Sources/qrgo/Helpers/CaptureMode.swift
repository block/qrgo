import Foundation

enum CaptureMode: String, Equatable {
    case drag
    case click

    var selectionPrompt: String {
        switch self {
        case .drag:
            return "Please select the area containing the QR code…"
        case .click:
            return "Move the square over the QR code and click to capture. Press Esc to cancel."
        }
    }

    static func parse(arguments: [String]) throws -> CaptureMode {
        var selection: CaptureMode?
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            let value: String
            if argument == "--capture-mode" {
                index += 1
                guard index < arguments.count else { throw ArgumentError.missingValue }
                value = arguments[index]
            } else if argument.hasPrefix("--capture-mode=") {
                value = String(argument.dropFirst("--capture-mode=".count))
            } else {
                index += 1
                continue
            }
            guard selection == nil else { throw ArgumentError.repeatedOption }
            guard let mode = CaptureMode(rawValue: value) else { throw ArgumentError.invalidValue(value) }
            selection = mode
            index += 1
        }
        if selection != nil && arguments.contains(where: {
            ["--menu-bar", "--menu-bar-agent", "--open-last"].contains($0)
        }) {
            throw ArgumentError.requiresCLIScan
        }
        return selection ?? .drag
    }

    enum ArgumentError: LocalizedError, Equatable {
        case missingValue
        case invalidValue(String)
        case repeatedOption
        case requiresCLIScan

        var errorDescription: String? {
            switch self {
            case .missingValue:
                return "--capture-mode requires 'click' or 'drag'."
            case .invalidValue(let value):
                return "Invalid capture mode '\(value)'. Use 'click' or 'drag'."
            case .repeatedOption:
                return "Specify --capture-mode only once."
            case .requiresCLIScan:
                return "--capture-mode is available only for CLI scans. Change menu bar capture mode in Settings."
            }
        }
    }
}
