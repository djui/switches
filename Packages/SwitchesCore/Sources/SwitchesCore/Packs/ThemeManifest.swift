/// `theme.json` written by `scripts/convert_sounds.swift` next to the theme's CAF samples.
public struct ThemeManifest: Codable, Sendable, Equatable {
    public struct KeySamples: Codable, Sendable, Equatable {
        /// File name of the key-down sample, e.g. `0-down.caf`.
        public var down: String
        /// File name of the key-up sample; `nil` plays nothing on release.
        public var up: String?

        public init(down: String, up: String? = nil) {
            self.down = down
            self.up = up
        }
    }

    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var name: String
    public var sampleRate: Double
    public var channels: Int
    /// Original pack format, e.g. `per-key-wav` or `mechvibes-single`.
    public var source: String?
    /// Keyed by decimal `CGKeyCode`.
    public var keys: [String: KeySamples]
    /// `KeyGroup` raw value → `CGKeyCode` whose samples stand in for missing keys of that group.
    public var fallbacks: [String: UInt16]

    public init(
        formatVersion: Int = ThemeManifest.currentFormatVersion,
        name: String,
        sampleRate: Double = 48_000,
        channels: Int = 1,
        source: String? = nil,
        keys: [String: KeySamples],
        fallbacks: [String: UInt16] = [:]
    ) {
        self.formatVersion = formatVersion
        self.name = name
        self.sampleRate = sampleRate
        self.channels = channels
        self.source = source
        self.keys = keys
        self.fallbacks = fallbacks
    }
}
