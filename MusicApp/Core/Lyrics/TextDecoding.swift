import Foundation

enum TextDecoding {
    /// Decodes lyrics files that may be UTF-8, UTF-16 (with BOM) or GBK/GB18030 (common for Chinese .lrc files).
    static func decodeText(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(3))
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            return String(data: data, encoding: .utf16LittleEndian).map(stripBOM)
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            return String(data: data, encoding: .utf16BigEndian).map(stripBOM)
        }
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        #if canImport(Darwin)
        let gb18030 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        ))
        if let chinese = String(data: data, encoding: gb18030) {
            return chinese
        }
        #endif
        return String(data: data, encoding: .isoLatin1)
    }

    private static func stripBOM(_ string: String) -> String {
        string.hasPrefix("\u{FEFF}") ? String(string.dropFirst()) : string
    }
}
