import Foundation

enum Terminal: String, Codable, CaseIterable, Identifiable {
    case ghostty
    case iterm

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        }
    }

    var appName: String {
        switch self {
        case .ghostty: return "Ghostty"
        case .iterm: return "iTerm"
        }
    }
}
