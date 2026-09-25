import Foundation

/// Decodes a field that is sometimes a String and sometimes an array of Strings (Internet Archive).
struct StringOrArray: Decodable, Hashable, Sendable {
    var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let single = try? container.decode(String.self) {
            values = [single]
        } else if let many = try? container.decode([String].self) {
            values = many
        } else if let number = try? container.decode(Double.self) {
            values = [FlexibleString.format(number)]
        } else {
            values = []
        }
    }

    var first: String? { values.first(where: { !$0.isEmpty }) }
    var joined: String? {
        let nonEmpty = values.filter { !$0.isEmpty }
        return nonEmpty.isEmpty ? nil : nonEmpty.joined(separator: ", ")
    }
}

/// Decodes a scalar that may be sent as a String, Int or Double.
struct FlexibleString: Decodable, Hashable, Sendable {
    var value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let int = try? container.decode(Int.self) {
            value = String(int)
        } else if let double = try? container.decode(Double.self) {
            value = Self.format(double)
        } else if let bool = try? container.decode(Bool.self) {
            value = bool ? "true" : "false"
        } else {
            value = ""
        }
    }

    static func format(_ double: Double) -> String {
        if double.rounded() == double, abs(double) < 1e15 { return String(Int(double)) }
        return String(double)
    }
}

/// An array that skips elements which fail to decode instead of failing the whole payload.
@propertyWrapper
struct LossyArray<Element: Decodable>: Decodable {
    var wrappedValue: [Element]

    init(wrappedValue: [Element]) {
        self.wrappedValue = wrappedValue
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            // `Attempt` never throws, so the container always advances past bad elements.
            if let element = try container.decode(Attempt.self).value {
                elements.append(element)
            }
        }
        wrappedValue = elements
    }

    private struct Attempt: Decodable {
        let value: Element?

        init(from decoder: Decoder) throws {
            value = try? Element(from: decoder)
        }
    }
}

extension KeyedDecodingContainer {
    /// Missing or null `LossyArray` keys decode as an empty array.
    func decode<T>(_ type: LossyArray<T>.Type, forKey key: Key) throws -> LossyArray<T> {
        try decodeIfPresent(type, forKey: key) ?? LossyArray(wrappedValue: [])
    }
}

extension String {
    /// nil for empty or whitespace-only strings.
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Optional where Wrapped == String {
    var nonEmpty: String? { self?.nonEmpty }
}
