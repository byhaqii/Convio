import Foundation
import CryptoKit

enum UpdateValidation {
    static func verifyArchive(_ url: URL, sha256: String) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 100_000_000 else { throw UpdateError("Invalid update download size.") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == sha256 else { throw UpdateError("The update checksum did not match. Nothing was installed.") }
    }

    static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError("Update validation failed: \(URL(fileURLWithPath: executable).lastPathComponent).") }
    }

    static func verifyBundle(_ url: URL, version: String) throws {
        guard try url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink == false,
              let bundle = Bundle(url: url), bundle.bundleIdentifier == "com.shustle.convio",
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version,
              let minimum = bundle.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String,
              let executable = bundle.executableURL, executable.lastPathComponent == "Convio",
              FileManager.default.fileExists(atPath: executable.path) else {
            throw UpdateError("The downloaded app is not the expected Convio version.")
        }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let currentOS = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        guard minimum.compare(currentOS, options: .numeric) != .orderedDescending else {
            throw UpdateError("This update requires macOS \(minimum) or later.")
        }
        try run("/usr/bin/lipo", [executable.path, "-verify_arch", "arm64"])
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path])
    }
}
