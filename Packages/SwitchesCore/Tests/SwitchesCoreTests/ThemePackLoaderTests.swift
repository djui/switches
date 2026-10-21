import AVFoundation
import Foundation
import Testing
@testable import SwitchesCore

struct ThemePackLoaderTests {
    private static let repoThemes = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Switches/Resources/Themes")

    private func makeTheme(rate: Double = 48_000) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwitchesTests-\(UUID().uuidString)/Test", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try writeSine(to: dir.appendingPathComponent("0-down.caf"), frames: 2_400, rate: rate)
        try writeSine(to: dir.appendingPathComponent("0-up.caf"), frames: 1_200, rate: rate)
        try writeSine(to: dir.appendingPathComponent("49-down.caf"), frames: 3_000, rate: rate)
        let manifest = ThemeManifest(
            name: "Test",
            keys: [
                "0": .init(down: "0-down.caf", up: "0-up.caf"),
                "49": .init(down: "49-down.caf"),
            ],
            fallbacks: ["alpha": 0, "space": 49]
        )
        try JSONEncoder().encode(manifest).write(to: dir.appendingPathComponent("theme.json"))
        return dir
    }

    private func writeSine(to url: URL, frames: Int, rate: Double) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for i in 0..<frames { buffer.floatChannelData![0][i] = 0.5 * sin(Float(i) * 0.1) }
        try file.write(from: buffer)
    }

    @Test func loadsManifestAndSamples() throws {
        let dir = try makeTheme()
        let pack = try ThemePackLoader.load(from: dir)
        #expect(pack.name == "Test")
        #expect(pack.bank.buffers.count == 3)
        let down = try #require(pack.sample(for: 0, group: .alpha, isDown: true))
        #expect(down.count == 2_400)
        #expect(down.sampleRate == 48_000)
        #expect(pack.sample(for: 0, group: .alpha, isDown: false)?.count == 1_200)
    }

    @Test func missingKeysUseGroupFallback() throws {
        let pack = try ThemePackLoader.load(from: try makeTheme())
        #expect(pack.sample(for: 12, group: .alpha, isDown: true)?.count == 2_400)
        #expect(pack.sample(for: 49, group: .space, isDown: true)?.count == 3_000)
        #expect(pack.sample(for: 49, group: .space, isDown: false) == nil)
        #expect(pack.sample(for: 36, group: .enter, isDown: true)?.count == 2_400)
    }

    @Test func resamplesToFortyEightKilohertz() throws {
        let pack = try ThemePackLoader.load(from: try makeTheme(rate: 44_100))
        let down = try #require(pack.sample(for: 0, group: .alpha, isDown: true))
        #expect(abs(down.count - 2_612) < 16)
    }

    @Test func packStoreListsThemes() throws {
        let dir = try makeTheme()
        let store = PackStore(directory: dir.deletingLastPathComponent())
        #expect(store.themeNames() == ["Test"])
        #expect(try store.loadTheme(named: "Test").bank.buffers.count == 3)
    }

    @Test func missingManifestThrows() {
        #expect(throws: ThemePackError.self) {
            try ThemePackLoader.load(from: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        }
    }

    @Test(.enabled(if: FileManager.default.fileExists(atPath: repoThemes.appendingPathComponent("Cardboard/theme.json").path)))
    func convertedThemesLoad() throws {
        let store = PackStore(directory: Self.repoThemes)
        #expect(!store.themeNames().isEmpty)
        for name in store.themeNames() {
            let pack = try store.loadTheme(named: name)
            #expect(pack.manifest.sampleRate == 48_000)
            #expect(pack.manifest.channels == 1)
            #expect(pack.sample(for: 0, group: .alpha, isDown: true) != nil, "\(name) has no A key")
            #expect(pack.sample(for: 49, group: .space, isDown: true) != nil, "\(name) has no space")
        }
    }
}
