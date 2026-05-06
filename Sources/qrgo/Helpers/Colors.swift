import Foundation

enum Colors {
    static let red = "\u{001B}[31m"
    static let green = "\u{001B}[32m"
    static let yellow = "\u{001B}[33m"
    static let blue = "\u{001B}[34m"
    static let gray = "\u{001B}[90m"
    static let bold = "\u{001B}[1m"
    static let reset = "\u{001B}[0m"
}

func printError(_ message: String) {
    print("\(Colors.red)\(message)\(Colors.reset)")
}

func printSuccess(_ message: String) {
    print("\(Colors.green)\(message)\(Colors.reset)")
}

func printWarning(_ message: String) {
    print("\(Colors.yellow)\(message)\(Colors.reset)")
}

func printInfo(_ message: String) {
    print("\(Colors.blue)\(message)\(Colors.reset)")
}

func printTip(_ message: String) {
    print("\(Colors.gray)\(message)\(Colors.reset)")
}
