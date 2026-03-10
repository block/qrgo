import Foundation

/// Validates and sanitizes a URL string for safe use with Android shell commands via `adb shell am start -d`.
///
/// Because `adb shell` invokes the Android `/bin/sh`, shell metacharacters in the URL would be
/// interpreted as shell syntax rather than as URL data. This function:
///   1. Rejects malformed URLs
///   2. Enforces an allowlist of URL schemes
///   3. Re-serializes via `URL` (which normalizes percent-encoding)
///   4. Rejects any characters with special meaning to POSIX shells
///
/// Note: percent-encoded metacharacters (e.g. `%3B` for `;`) survive safely — they appear as
/// literal `%`, digit, and letter characters in the serialized string, none of which are dangerous.
///
/// - Parameters:
///   - urlString: The raw URL string to validate.
///   - allowedSchemes: Set of lowercase scheme strings to permit. Defaults to `["http", "https", "cashme"]`.
/// - Returns: The normalized URL string if valid, or `nil` if it should be rejected.
public func sanitizeUrlForAndroidShell(
    _ urlString: String,
    allowedSchemes: Set<String> = ["http", "https", "cashme"]
) -> String? {
    guard let url = URL(string: urlString) else { return nil }

    guard let scheme = url.scheme?.lowercased(), allowedSchemes.contains(scheme) else { return nil }

    // Re-serialize to normalize percent-encoding
    let sanitized = url.absoluteString

    // Reject shell metacharacters. Note: space is included as a safety net even though
    // URL(string:) percent-encodes spaces in path/query components.
    let dangerous = CharacterSet(charactersIn: ";&|><`$()\\\"'\r\n\0 ")
    guard !sanitized.unicodeScalars.contains(where: { dangerous.contains($0) }) else { return nil }

    return sanitized
}
