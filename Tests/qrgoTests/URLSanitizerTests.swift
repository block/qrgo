import XCTest
@testable import qrgoLib

final class URLSanitizerTests: XCTestCase {

    // MARK: - Valid URLs

    func testHttpUrlPassesThrough() {
        let result = sanitizeUrlForAndroidShell("http://example.com/path?query=value")
        XCTAssertEqual(result, "http://example.com/path?query=value")
    }

    func testHttpsUrlPassesThrough() {
        let result = sanitizeUrlForAndroidShell("https://cash.app/some/path")
        XCTAssertEqual(result, "https://cash.app/some/path")
    }

    func testCashmeDeepLinkPassesThrough() {
        let result = sanitizeUrlForAndroidShell("cashme://pay/john")
        XCTAssertEqual(result, "cashme://pay/john")
    }

    func testUrlWithFragmentPassesThrough() {
        let result = sanitizeUrlForAndroidShell("https://example.com/page#section")
        XCTAssertEqual(result, "https://example.com/page#section")
    }

    func testUrlWithPortPassesThrough() {
        let result = sanitizeUrlForAndroidShell("http://localhost:8080/path")
        XCTAssertEqual(result, "http://localhost:8080/path")
    }

    // MARK: - Percent-encoded metacharacters are safe

    func testPercentEncodedSemicolonIsAllowed() {
        // %3B decodes to ';' but appears as literal %3B in the serialized string — safe
        let result = sanitizeUrlForAndroidShell("https://example.com/path%3Breboot")
        XCTAssertEqual(result, "https://example.com/path%3Breboot")
    }

    func testPercentEncodedDollarIsAllowed() {
        let result = sanitizeUrlForAndroidShell("https://example.com/path%24var")
        XCTAssertEqual(result, "https://example.com/path%24var")
    }

    func testPercentEncodedPipeIsAllowed() {
        let result = sanitizeUrlForAndroidShell("https://example.com/%7Cpath")
        XCTAssertEqual(result, "https://example.com/%7Cpath")
    }

    // MARK: - Scheme allowlist

    func testJavascriptSchemeIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("javascript:alert(1)"))
    }

    func testFileSchemeIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("file:///etc/passwd"))
    }

    func testFtpSchemeIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("ftp://example.com/file"))
    }

    func testCustomSchemeNotInAllowlistIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("myapp://action"))
    }

    func testCustomSchemeInAllowlistIsAccepted() {
        let result = sanitizeUrlForAndroidShell("myapp://action", allowedSchemes: ["myapp"])
        XCTAssertEqual(result, "myapp://action")
    }

    // MARK: - Shell metacharacter injection

    func testSemicolonInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com;reboot"))
    }

    func testAmpersandInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com&id"))
    }

    func testPipeInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com|cat /etc/passwd"))
    }

    func testBacktickInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com`id`"))
    }

    func testDollarSignInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com$(id)"))
    }

    func testCommandSubstitutionInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com$(reboot)"))
    }

    func testRedirectInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com>/tmp/out"))
    }

    func testNewlineInjectionIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("http://example.com\nreboot"))
    }

    // MARK: - Malformed URLs

    func testEmptyStringIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell(""))
    }

    func testNoSchemeIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("example.com/path"))
    }

    func testGibberishIsRejected() {
        XCTAssertNil(sanitizeUrlForAndroidShell("not a url at all!!"))
    }
}
