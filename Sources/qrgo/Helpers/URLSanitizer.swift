import Foundation

/// The canonical allowlist of URL schemes permitted for opening on Android devices.
/// This is the single source of truth used by both the sanitizer and error reporting.
let allowedUrlSchemes: Set<String> = ["http", "https", "cashme"]

/// Reasons a URL can be rejected by `sanitizeUrlForAndroidShell`.
enum URLSanitizationError: Error {
    case malformed
    case disallowedScheme(String)
    case dangerousCharacters
}

/// Validates and sanitizes a URL string for safe use inside a single-quoted POSIX shell argument.
///
/// This function does NOT reject shell metacharacters like `&`, `;`, or `|` — those are safe
/// when the URL is wrapped in single quotes by the caller (e.g. `"am start -d '\(safe)'"` passed
/// as a single command string to `adb shell`). It only rejects characters that can break out of
/// single-quoted strings themselves.
///
/// This function:
///   1. Rejects malformed URLs
///   2. Enforces an allowlist of URL schemes
///   3. Re-serializes via `URL` (which normalizes percent-encoding)
///   4. Rejects characters that can break out of a single-quoted POSIX string: `'`, `\0`, `\r`, `\n`
///
/// - Parameters:
///   - urlString: The raw URL string to validate.
///   - allowedSchemes: Set of lowercase scheme strings to permit. Defaults to `allowedUrlSchemes`.
/// - Returns: The normalized URL string on success, or a `URLSanitizationError` describing the failure.
func sanitizeUrlForAndroidShell(
    _ urlString: String,
    allowedSchemes: Set<String> = allowedUrlSchemes
) -> Result<String, URLSanitizationError> {
    guard let url = URL(string: urlString) else { return .failure(.malformed) }

    let scheme = url.scheme?.lowercased() ?? ""
    guard allowedSchemes.contains(scheme) else { return .failure(.disallowedScheme(scheme)) }

    // Re-serialize to normalize percent-encoding
    let sanitized = url.absoluteString

    // Reject characters that can break out of a single-quoted POSIX shell string.
    // The caller is responsible for wrapping the result in single quotes.
    let dangerous = CharacterSet(charactersIn: "'\r\n\0")
    guard !sanitized.unicodeScalars.contains(where: { dangerous.contains($0) }) else {
        return .failure(.dangerousCharacters)
    }

    return .success(sanitized)
}
