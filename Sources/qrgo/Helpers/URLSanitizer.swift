import Foundation

/// Allowed URL schemes for opening on Android devices.
let allowedUrlSchemes: Set<String> = ["http", "https", "cashme"]

/// Validates and sanitizes a URL string for safe embedding in a single-quoted POSIX shell argument.
///
/// Because `adb shell` joins its arguments with spaces and passes the result to the Android
/// device's `/bin/sh`, the caller must wrap the returned string in single quotes (e.g.
/// `"-d", "'\(safe)'"`) to prevent shell interpretation of characters like `&`, `;`, `|`, etc.
///
/// This function:
///   1. Rejects malformed URLs
///   2. Enforces an allowlist of URL schemes
///   3. Re-serializes via `URL` (which normalizes percent-encoding)
///   4. Rejects characters that can break out of a single-quoted POSIX string: `'`, `\0`, `\r`, `\n`
///
/// Note: Characters like `&`, `;`, `|`, `>`, `<` are safe to return — they cannot escape
/// single quotes and will be treated literally by the shell when the caller wraps the URL
/// in single quotes.
///
/// - Parameters:
///   - urlString: The raw URL string to validate.
///   - allowedSchemes: Set of lowercase scheme strings to permit. Defaults to `allowedUrlSchemes`.
/// - Returns: The normalized URL string if valid, or `nil` if it should be rejected.
func sanitizeUrlForAndroidShell(
    _ urlString: String,
    allowedSchemes: Set<String> = allowedUrlSchemes
) -> String? {
    guard let url = URL(string: urlString) else { return nil }

    guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return nil }

    // Re-serialize to normalize percent-encoding
    let sanitized = url.absoluteString

    // Reject characters that can break out of a single-quoted POSIX shell string.
    // The caller is responsible for wrapping the result in single quotes.
    let dangerous = CharacterSet(charactersIn: "'\r\n\0")
    guard !sanitized.unicodeScalars.contains(where: { dangerous.contains($0) }) else { return nil }

    return sanitized
}
