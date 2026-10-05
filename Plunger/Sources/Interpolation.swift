import Foundation

enum Interpolation {
    static func render(_ template: String, values: [String: String]) -> String {
        guard !template.isEmpty else { return "" }

        var result = ""
        var index = template.startIndex
        let end = template.endIndex

        while index < end {
            let character = template[index]
            if character == "{",
               template.index(after: index) < end,
               template[template.index(after: index)] == "{" {
                let openStart = index
                let searchStart = template.index(index, offsetBy: 2)
                if let closeRange = template.range(of: "}}", range: searchStart..<end) {
                    let name = template[searchStart..<closeRange.lowerBound]
                        .trimmingCharacters(in: .whitespaces)
                    if let value = values[name] {
                        result += value
                    } else {
                        result += template[openStart..<closeRange.upperBound]
                    }
                    index = closeRange.upperBound
                } else {
                    result += template[openStart..<end]
                    index = end
                }
            } else {
                result.append(character)
                index = template.index(after: index)
            }
        }

        return result
    }
}
