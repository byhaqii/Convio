import Foundation
import Darwin

final class InstanceLock {
    private let descriptor: Int32

    init?(url: URL) throws {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let failure = errno
            close(descriptor)
            if failure == EWOULDBLOCK { return nil }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
        self.descriptor = descriptor
    }

    deinit { close(descriptor) }
}
