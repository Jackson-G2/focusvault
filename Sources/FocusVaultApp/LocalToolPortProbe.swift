import Darwin
import Foundation

/// Probes only loopback TCP; it never fetches links or discovers remote hosts.
enum LocalToolPortProbe {
    static func isOpen(_ port: Int) -> Bool {
        guard (1...65_535).contains(port) else { return false }
        var ipv4 = sockaddr_in()
        ipv4.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        ipv4.sin_family = sa_family_t(AF_INET)
        ipv4.sin_port = in_port_t(port).bigEndian
        ipv4.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let v4Open = withUnsafePointer(to: &ipv4) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connects(family: AF_INET, address: $0, length: socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if v4Open { return true }

        var ipv6 = sockaddr_in6()
        ipv6.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
        ipv6.sin6_family = sa_family_t(AF_INET6)
        ipv6.sin6_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET6, "::1", &ipv6.sin6_addr) == 1 else { return false }
        return withUnsafePointer(to: &ipv6) { address in
            address.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connects(family: AF_INET6, address: $0, length: socklen_t(MemoryLayout<sockaddr_in6>.size))
            }
        }
    }

    private static func connects(family: Int32, address: UnsafePointer<sockaddr>, length: socklen_t) -> Bool {
        let descriptor = socket(family, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        let flags = fcntl(descriptor, F_GETFL, 0)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { return false }
        if Darwin.connect(descriptor, address, length) == 0 { return true }
        guard errno == EINPROGRESS else { return false }

        // poll works above FD_SETSIZE; constructing fd_set/select with an
        // arbitrary descriptor can read beyond its fixed-capacity bitset.
        var readiness = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
        guard poll(&readiness, 1, 300) > 0, readiness.revents & Int16(POLLNVAL) == 0 else { return false }
        var socketError: Int32 = 0
        var errorLength = socklen_t(MemoryLayout<Int32>.size)
        return getsockopt(descriptor, SOL_SOCKET, SO_ERROR, &socketError, &errorLength) == 0 && socketError == 0
    }
}

extension LocalToolsManager {
    nonisolated static func portIsOpen(_ port: Int) -> Bool { LocalToolPortProbe.isOpen(port) }
}
