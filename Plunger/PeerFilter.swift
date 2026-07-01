//
//  PeerFilter.swift
//  Plunger
//
//  Decides whether an incoming connection's source IP is allowed, so the HTTP
//  server can restrict access to chosen networks (loopback, Tailscale, LAN, or
//  any) on top of the bearer token. The categories are independent: a peer is
//  allowed if its IP falls in any enabled category. An empty set allows nothing
//  — not even loopback — so "allow only what you check" is literal.
//
//  Matching is pure and works on a parsed IP, so it is unit-testable without a
//  live socket. Tailscale hands every node an address in 100.64.0.0/10 (the
//  CGNAT range), so that single CIDR identifies tailnet traffic.
//

import Foundation

/// A source-network category the server may allow. Order is the display order.
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
    /// 4 bytes for IPv4, 16 for IPv6.
    let bytes: [UInt8]

    var isIPv4: Bool { bytes.count == 4 }

    /// Builds a PeerIP from raw address bytes (4 for IPv4, 16 for IPv6), as
    /// NWEndpoint.Host's IPv4Address/IPv6Address rawValue supplies. Collapses an
    /// IPv4-mapped IPv6 address to its 4-byte IPv4 form.
    init?(rawBytes: Data) {
        let all = [UInt8](rawBytes)
        if all.count == 4 {
            bytes = all
            return
        }
        if all.count == 16 {
            let prefix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff]
            bytes = Array(all.prefix(12)) == prefix ? Array(all.suffix(4)) : all
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
            let all = withUnsafeBytes(of: v6) { Array($0) }
            // IPv4-mapped (::ffff:0:0/96): last 4 bytes are the real IPv4.
            let prefix: [UInt8] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff]
            if all.count == 16, Array(all.prefix(12)) == prefix {
                bytes = Array(all.suffix(4))
            } else {
                bytes = all
            }
            return
        }

        return nil
    }
}

/// Which peers the server accepts. Pure decision logic; the server supplies the
/// parsed peer IP.
struct PeerFilter {
    let allowed: Set<PeerCategory>

    /// Reports whether a peer at `ip` is allowed by the enabled categories.
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
