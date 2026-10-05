import Foundation

enum PeerCategory: String, CaseIterable, Codable, Identifiable {
    case loopback
    case tailscale
    case localNetwork
    case any

    var id: String { rawValue }

    var label: String {
        switch self {
        case .loopback: "Loopback"
        case .tailscale: "Tailscale"
        case .localNetwork: "Local network"
        case .any: "Any"
        }
    }

    var detail: String {
        switch self {
        case .loopback: "127.0.0.1, ::1 — this Mac"
        case .tailscale: "100.64.0.0/10 — your tailnet"
        case .localNetwork: "Private LAN (10/8, 172.16/12, 192.168/16, link-local)"
        case .any: "No restriction (0.0.0.0/0)"
        }
    }
}

/// A parsed IPv4 or IPv6 address, reduced to a big-endian byte array. IPv4-
/// mapped IPv6 (`::ffff:a.b.c.d`) collapses to its 4-byte IPv4 form so a
/// dual-stack peer matches IPv4 rules.
struct PeerIP: Equatable {
    let bytes: [UInt8]

    var isIPv4: Bool { bytes.count == 4 }

    init?(rawBytes: Data) {
        let all = [UInt8](rawBytes)
        if all.count == 4 {
            bytes = all
            return
        }
        if all.count == 16 {
            bytes = Self.collapseMapped(all)
            return
        }
        return nil
    }

    init?(_ text: String) {
        // Strip a zone id (e.g. "fe80::1%en0") before parsing.
        let address = text.split(separator: "%", maxSplits: 1).first.map(String.init) ?? text

        var v4 = in_addr()
        if inet_pton(AF_INET, address, &v4) == 1 {
            bytes = withUnsafeBytes(of: v4.s_addr) { Array($0) }
            return
        }

        var v6 = in6_addr()
        if inet_pton(AF_INET6, address, &v6) == 1 {
            bytes = Self.collapseMapped(withUnsafeBytes(of: v6) { Array($0) })
            return
        }

        return nil
    }

    private static func collapseMapped(_ all: [UInt8]) -> [UInt8] {
        let prefix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff]
        guard all.count == 16, Array(all.prefix(12)) == prefix else { return all }
        return Array(all.suffix(4))
    }
}

struct PeerFilter {
    let allowed: Set<PeerCategory>

    func allows(_ ip: PeerIP) -> Bool {
        if allowed.contains(.any) { return true }
        for category in allowed where Self.matches(ip, category) {
            return true
        }
        return false
    }

    private static func matches(_ ip: PeerIP, _ category: PeerCategory) -> Bool {
        switch category {
        case .any:
            return true
        case .loopback:
            return isLoopback(ip)
        case .tailscale:
            // 100.64.0.0/10
            return ip.isIPv4 && ip.bytes[0] == 100 && (ip.bytes[1] & 0xC0) == 64
        case .localNetwork:
            return isPrivateLAN(ip)
        }
    }

    private static func isLoopback(_ ip: PeerIP) -> Bool {
        if ip.isIPv4 { return ip.bytes[0] == 127 }
        // ::1
        return ip.bytes == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    }

    private static func isPrivateLAN(_ ip: PeerIP) -> Bool {
        if ip.isIPv4 {
            let b = ip.bytes
            if b[0] == 10 { return true }                          // 10.0.0.0/8
            if b[0] == 172 && (b[1] & 0xF0) == 16 { return true }  // 172.16.0.0/12
            if b[0] == 192 && b[1] == 168 { return true }          // 192.168.0.0/16
            if b[0] == 169 && b[1] == 254 { return true }          // 169.254.0.0/16 link-local
            return false
        }
        // IPv6 unique-local fc00::/7 and link-local fe80::/10.
        let first = ip.bytes[0]
        if (first & 0xFE) == 0xFC { return true }
        if first == 0xFE && (ip.bytes[1] & 0xC0) == 0x80 { return true }
        return false
    }
}
