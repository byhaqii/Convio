import Foundation

struct UpdateError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

struct UpdateRelease: Sendable {
    let version: String
    let url: URL
    let sha256: String

    static func versionNumbers(_ version: String) throws -> [Int] {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw UpdateError("Invalid release version.") }
        return try parts.map { part in
            guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
                  let number = Int(part) else { throw UpdateError("Invalid release version.") }
            return number
        }
    }

    static func parse(_ data: Data, currentVersion: String) throws -> UpdateRelease? {
        struct Release: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: String
                let digest: String?
            }
            let tag_name: String
            let draft: Bool
            let prerelease: Bool
            let assets: [Asset]
        }
        let release = try JSONDecoder().decode(Release.self, from: data)
        guard !release.draft, !release.prerelease, release.tag_name.hasPrefix("v") else {
            throw UpdateError("The release is not a stable Convy version.")
        }
        let version = String(release.tag_name.dropFirst())
        let numbers = try versionNumbers(version)
        let current = try versionNumbers(currentVersion)
        guard current.lexicographicallyPrecedes(numbers) else { return nil }
        let name = "Convy-\(version)-arm64.zip"
        let expected = "https://github.com/byhaqii/Convy/releases/download/v\(version)/\(name)"
        guard let asset = release.assets.first(where: { $0.name == name }),
              asset.browser_download_url == expected, let url = URL(string: expected),
              let digest = asset.digest, digest.hasPrefix("sha256:") else {
            throw UpdateError("The release is missing a trusted download or SHA-256 checksum.")
        }
        let hash = String(digest.dropFirst(7)).lowercased()
        guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw UpdateError("The release checksum is invalid.")
        }
        return UpdateRelease(version: version, url: url, sha256: hash)
    }
}

enum UpdateSafety {
    static func requireIdle(windowBusy: Bool, wheelBusy: Bool) throws {
        guard !windowBusy, !wheelBusy else {
            throw UpdateError("Wait for the current conversion to finish before updating.")
        }
    }
}
