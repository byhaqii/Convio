import Foundation

@main struct UpdateTests {
    static func main() throws {
        func metadata(_ version: String = "0.4.10", digest: String? = "sha256:" + String(repeating: "a", count: 64), url: String? = nil, prerelease: Bool = false) throws -> Data {
            var asset: [String: Any] = ["name": "Convy-\(version)-arm64.zip",
                "browser_download_url": url ?? "https://github.com/byhaqii/Convy/releases/download/v\(version)/Convy-\(version)-arm64.zip"]
            asset["digest"] = digest
            return try JSONSerialization.data(withJSONObject: ["tag_name": "v" + version,
                "draft": false, "prerelease": prerelease, "assets": [asset]])
        }
        let release = try UpdateRelease.parse(metadata(), currentVersion: "0.4.9")
        precondition(release?.version == "0.4.10")
        precondition(release?.sha256 == String(repeating: "a", count: 64))
        let equal = try UpdateRelease.parse(metadata("0.4.9"), currentVersion: "0.4.9")
        precondition(equal == nil)
        let older = try UpdateRelease.parse(metadata("0.4.8"), currentVersion: "0.4.9")
        precondition(older == nil)
        for data in try [metadata("oops"), metadata(digest: nil), metadata(digest: "sha256:abc"),
            metadata(url: "https://evil.example/app.zip"), metadata(prerelease: true)] {
            do {
                _ = try UpdateRelease.parse(data, currentVersion: "0.4.9")
                preconditionFailure("Untrusted or invalid release accepted")
            } catch {}
        }
        try UpdateSafety.requireIdle(windowBusy: false, wheelBusy: false)
        for (window, wheel) in [(true, false), (false, true), (true, true)] {
            do {
                try UpdateSafety.requireIdle(windowBusy: window, wheelBusy: wheel)
                preconditionFailure("Update allowed during conversion")
            } catch {}
        }
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: archive) }
        try Data("abc".utf8).write(to: archive)
        try UpdateValidation.verifyArchive(archive, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        do {
            try UpdateValidation.verifyArchive(archive, sha256: String(repeating: "0", count: 64))
            preconditionFailure("Corrupted download accepted")
        } catch {}
        do {
            try UpdateValidation.verifyBundle(archive, version: "0.4.10")
            preconditionFailure("Invalid app bundle accepted")
        } catch {}
        if CommandLine.arguments.count > 1 {
            let app = URL(fileURLWithPath: CommandLine.arguments[1])
            guard let version = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else {
                preconditionFailure("Missing app version")
            }
            try UpdateValidation.verifyBundle(app, version: version)
        }
        print("PASS: numeric versions, older/equal releases, metadata trust boundary, conversion interlock")
    }
}
