import Foundation

public enum ThemePackError: Error, LocalizedError {
    case missingManifest(URL)
    case unsupportedFormat(Int)
    case noSamples(String)

    public var errorDescription: String? {
        switch self {
        case let .missingManifest(url): "No theme.json in \(url.lastPathComponent)"
        case let .unsupportedFormat(version): "Unsupported theme format version \(version)"
        case let .noSamples(name): "Theme \(name) has no samples"
        }
    }
}

/// A loaded theme: manifest plus decoded samples, with key-code lookup and group fallbacks.
public final class ThemePack: @unchecked Sendable {
    public let name: String
    public let manifest: ThemeManifest
    public let bank: SampleBank

    private let down: [UInt16: Int]
    private let up: [UInt16: Int]
    private let fallbackKeys: [KeyGroup: UInt16]
    private let alphaKeys: [UInt16]

    init(name: String, manifest: ThemeManifest, bank: SampleBank, down: [UInt16: Int], up: [UInt16: Int]) {
        self.name = name
        self.manifest = manifest
        self.bank = bank
        self.down = down
        self.up = up
        var fallbacks: [KeyGroup: UInt16] = [:]
        for (group, code) in manifest.fallbacks {
            if let group = KeyGroup(rawValue: group), down[code] != nil { fallbacks[group] = code }
        }
        self.fallbackKeys = fallbacks
        let alpha = down.keys.filter { KeyLayout.group(for: $0) == .alpha }.sorted()
        self.alphaKeys = alpha.isEmpty ? down.keys.sorted() : alpha
    }

    public var keyCodes: [UInt16] { down.keys.sorted() }

    public func hasOwnSample(for keyCode: UInt16) -> Bool { down[keyCode] != nil }

    /// Sample for a key, falling back to the group's stand-in key and then to a stable
    /// alpha key so every physical key makes a sound.
    public func sample(for keyCode: UInt16, group: KeyGroup, isDown: Bool) -> SampleBuffer? {
        let source = resolve(keyCode, group: group)
        guard let source, let index = isDown ? down[source] : up[source] else { return nil }
        return bank.buffers[index]
    }

    private func resolve(_ keyCode: UInt16, group: KeyGroup) -> UInt16? {
        if down[keyCode] != nil { return keyCode }
        if let fallback = fallbackKeys[group] { return fallback }
        if group != .alpha, let fallback = fallbackKeys[.alpha] { return fallback }
        guard !alphaKeys.isEmpty else { return nil }
        return alphaKeys[Int(keyCode) % alphaKeys.count]
    }
}

public enum ThemePackLoader {
    public static let manifestFileName = "theme.json"

    public static func loadManifest(from directory: URL) throws -> ThemeManifest {
        let url = directory.appendingPathComponent(manifestFileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ThemePackError.missingManifest(directory)
        }
        let manifest = try JSONDecoder().decode(ThemeManifest.self, from: Data(contentsOf: url))
        guard manifest.formatVersion <= ThemeManifest.currentFormatVersion else {
            throw ThemePackError.unsupportedFormat(manifest.formatVersion)
        }
        return manifest
    }

    public static func load(from directory: URL) throws -> ThemePack {
        let manifest = try loadManifest(from: directory)
        var files: [String] = []
        var fileIndex: [String: Int] = [:]
        func index(of file: String) -> Int {
            if let existing = fileIndex[file] { return existing }
            files.append(file)
            fileIndex[file] = files.count - 1
            return files.count - 1
        }

        var down: [UInt16: Int] = [:]
        var up: [UInt16: Int] = [:]
        for (key, samples) in manifest.keys.sorted(by: { $0.key < $1.key }) {
            guard let code = UInt16(key) else { continue }
            down[code] = index(of: samples.down)
            if let upFile = samples.up { up[code] = index(of: upFile) }
        }
        guard !files.isEmpty else { throw ThemePackError.noSamples(manifest.name) }

        let bank = try SampleBank(urls: files.map { directory.appendingPathComponent($0) })
        return ThemePack(
            name: directory.lastPathComponent,
            manifest: manifest,
            bank: bank,
            down: down,
            up: up
        )
    }
}
