import Foundation
import Testing
@testable import qrgo

struct ClickCaptureHelperTests {
    @Test func `helper returns capture coordinates including negative display origins`() throws {
        let result = makeResult(output: "[[-1200,-400],[362,362]]")
        #expect(try ClickCaptureHelper.selection(from: result) == CGRect(x: -1200, y: -400, width: 362, height: 362))
    }

    @Test func `explicit null means the user canceled`() throws {
        #expect(try ClickCaptureHelper.selection(from: makeResult(output: "null\n")) == nil)
    }

    @Test func `missing malformed and empty rectangles are errors rather than cancellation`() {
        for output in ["", "not JSON", "{}", "[[0,0],[0,362]]", "[[0,0],[362,-1]]"] {
            #expect(throws: ClickCaptureHelper.SelectionError.invalidResponse) {
                try ClickCaptureHelper.selection(from: makeResult(output: output))
            }
        }
    }

    @Test func `failed helper exits preserve the error even when output says null`() {
        let result = ShellResult(exitCode: 1, stdout: "null", stderr: "Helper failure", timedOut: false)
        #expect(throws: ClickCaptureHelper.SelectionError.failed("Helper failure")) {
            try ClickCaptureHelper.selection(from: result)
        }
    }

    private func makeResult(output: String) -> ShellResult {
        ShellResult(exitCode: 0, stdout: output, stderr: "", timedOut: false)
    }
}
