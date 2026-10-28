import Foundation
import Darwin

@main struct InstanceTests {
    static func main() throws {
        if CommandLine.arguments.count == 2 {
            let lock = try InstanceLock(url: URL(fileURLWithPath: CommandLine.arguments[1]))
            withExtendedLifetime(lock) { exit(lock == nil ? 73 : 0) }
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: path) }
        var owner = try InstanceLock(url: path)
        precondition(owner != nil)
        func probe() throws -> Int32 {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = [path.path]
            try child.run()
            child.waitUntilExit()
            return child.terminationStatus
        }
        let blocked = try probe()
        precondition(blocked == 73, "A second process acquired the wheel owner's lock")
        owner = nil
        let released = try probe()
        precondition(released == 0, "Exiting Convio left a stale lock")
        print("PASS: second process blocked; lock released when owner exits")
    }
}
