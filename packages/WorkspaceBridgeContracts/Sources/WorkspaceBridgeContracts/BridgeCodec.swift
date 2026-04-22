import Foundation

public enum BridgeCodec {
  private static func makeFormatterWithFractionalSeconds() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }

  public static func makeEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(makeFormatterWithFractionalSeconds().string(from: date))
    }
    return encoder
  }

  public static func makeDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let raw = try container.decode(String.self)
      if let value = makeFormatterWithFractionalSeconds().date(from: raw) {
        return value
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Expected ISO8601 date with fractional seconds, got: \(raw)"
      )
    }
    return decoder
  }
}
