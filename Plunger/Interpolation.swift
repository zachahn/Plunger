//
//  Interpolation.swift
//  Plunger
//
//  Substitutes `{{name}}` placeholders in a template string with values from
//  a lookup table. A single left-to-right scan, no regular expressions: an
//  unknown key or an unterminated `{{` is left in the output verbatim rather
//  than treated as an error.
//

import Foundation

enum Interpolation {
    /// Replaces each `{{name}}` in `template` with `values[name]`, trimming
    /// whitespace inside the braces before the lookup. A placeholder whose
    /// key is absent from `values` is left verbatim, braces included. A `{{`
    /// with no matching `}}` ends substitution and the remainder of the
    /// string is emitted unchanged.
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
