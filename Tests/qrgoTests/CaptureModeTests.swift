import Testing
@testable import qrgo

struct CaptureModeTests {
    @Test func `capture defaults to drag selection`() throws {
        #expect(try CaptureMode.parse(arguments: ["qrgo"]) == .drag)
        #expect(try CaptureMode.parse(arguments: ["qrgo", "--copy"]) == .drag)
        #expect(try CaptureMode.parse(arguments: ["qrgo", "--menu-bar"]) == .drag)
    }

    @Test func `both CLI modes accept separate and equals syntax`() throws {
        for mode in [CaptureMode.click, .drag] {
            #expect(try CaptureMode.parse(arguments: ["qrgo", "--capture-mode", mode.rawValue]) == mode)
            #expect(try CaptureMode.parse(arguments: ["qrgo", "--capture-mode=\(mode.rawValue)"]) == mode)
        }
    }

    @Test func `click selection combines with existing scan flags`() throws {
        #expect(try CaptureMode.parse(arguments: [
            "qrgo", "-d", "emulator-5554", "--capture-mode", "click", "--transform-urls"
        ]) == .click)
        #expect(try CaptureMode.parse(arguments: ["qrgo", "--copy", "--capture-mode=click"]) == .click)
    }

    @Test func `missing and invalid values produce actionable errors`() {
        #expect(throws: CaptureMode.ArgumentError.missingValue) {
            try CaptureMode.parse(arguments: ["qrgo", "--capture-mode"])
        }
        for value in ["", "square", "--copy"] {
            #expect(throws: CaptureMode.ArgumentError.invalidValue(value)) {
                try CaptureMode.parse(arguments: ["qrgo", "--capture-mode", value])
            }
        }
    }

    @Test func `repeated mode flags are rejected`() {
        #expect(throws: CaptureMode.ArgumentError.repeatedOption) {
            try CaptureMode.parse(arguments: ["qrgo", "--capture-mode=click", "--capture-mode", "drag"])
        }
    }

    @Test func `capture mode is rejected for commands that do not perform a CLI scan`() {
        for command in ["--menu-bar", "--menu-bar-agent", "--open-last"] {
            #expect(throws: CaptureMode.ArgumentError.requiresCLIScan) {
                try CaptureMode.parse(arguments: ["qrgo", command, "--capture-mode", "click"])
            }
        }
    }
}
