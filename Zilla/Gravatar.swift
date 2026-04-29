import Foundation
import CryptoKit
import SwiftUI

/// Computes the Gravatar URL for an email address. We compute it ourselves
/// rather than pulling in a Gravatar SDK because the only thing we need is the
/// URL — `AsyncImage` handles fetching, decoding, and caching, and the URL
/// derivation is a single MD5 + format-string.
enum Gravatar {
    /// Returns the avatar URL for `email`, or nil if the email is empty.
    /// `size` is the requested square pixel size. `d=404` makes the response a
    /// 404 when the user hasn't configured a Gravatar, so callers can show a
    /// platform-native placeholder via `AsyncImage`'s `.failure` case rather
    /// than a generic Gravatar silhouette.
    static func url(for email: String, size: Int = 64) -> URL? {
        let normalized = email
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        let hash = Insecure.MD5.hash(data: Data(normalized.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return URL(string: "https://www.gravatar.com/avatar/\(hash)?s=\(size)&d=404")
    }
}

/// A circular avatar that prefers a remote image (Gravatar by default) and
/// falls back to a `person.crop.circle.fill` placeholder when the image isn't
/// available. Used by activity rows and comment cards across the app.
struct UserAvatar: View {
    let email: String?
    var size: CGFloat = 28
    var imageURL: URL? = nil

    var body: some View {
        let pixelSize = Int(size * 3) // bias toward 3× for retina displays
        let resolvedURL: URL? = imageURL ?? email.flatMap { Gravatar.url(for: $0, size: pixelSize) }

        Group {
            if let resolvedURL {
                AsyncImage(url: resolvedURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        Image(systemName: "person.crop.circle.fill")
            .resizable()
            .foregroundStyle(.secondary)
    }
}
