import Foundation
import Observation

/// User settings, persisted in `UserDefaults`. Single source of truth for the UI and engine.
@MainActor
@Observable
public final class AppState {
    public enum Keys {
        public static let volume = "volume"
        public static let selectedTheme = "selectedTheme"
        public static let spatialWidth = "spatialWidth"
        public static let pitchVariance = "pitchVariance"
        public static let volumeVarianceDb = "volumeVarianceDb"
        public static let upGainDb = "upGainDb"
        public static let pitchSemitones = "pitchSemitones"
        public static let bassDb = "bassDb"
        public static let trebleDb = "trebleDb"
        public static let ignoreAutorepeat = "ignoreAutorepeat"
        public static let headphoneMode = "headphoneMode"
        public static let keyboardLayout = "keyboardLayout"
        public static let paused = "paused"
        public static let excludedBundleIDs = "excludedBundleIDs"
        public static let pauseForGames = "pauseForGames"
        public static let pauseInFullscreen = "pauseInFullscreen"
        public static let pauseOnSecureInput = "pauseOnSecureInput"
        public static let hotkeyEnabled = "hotkeyEnabled"
    }

    /// Factory values restored by the Reset buttons.
    public enum Defaults {
        public static let pitchVariance = 0.03
        public static let volumeVarianceDb = 1.5
        public static let upGainDb = -4.0
        public static let pitchSemitones = 0.0
        public static let bassDb = 0.0
        public static let trebleDb = 0.0
    }

    /// 0...1, perceptual; the mixer gain is `volume²`.
    public var volume: Double {
        didSet { defaults.set(volume, forKey: Keys.volume); pushGain(); changed() }
    }
    public var selectedTheme: String? {
        didSet { defaults.set(selectedTheme, forKey: Keys.selectedTheme); changed() }
    }
    /// 0 (mono) ... 1 (full left/right).
    public var spatialWidth: Double {
        didSet { defaults.set(spatialWidth, forKey: Keys.spatialWidth); changed() }
    }
    /// Max random playback-rate deviation, e.g. 0.03 = ±3 %.
    public var pitchVariance: Double {
        didSet { defaults.set(pitchVariance, forKey: Keys.pitchVariance); changed() }
    }
    /// Max random gain deviation in dB.
    public var volumeVarianceDb: Double {
        didSet { defaults.set(volumeVarianceDb, forKey: Keys.volumeVarianceDb); changed() }
    }
    /// Key-up level relative to key-down in dB.
    public var upGainDb: Double {
        didSet { defaults.set(upGainDb, forKey: Keys.upGainDb); changed() }
    }
    /// Fixed pitch shift of all sounds in semitones (negative = lower).
    public var pitchSemitones: Double {
        didSet { defaults.set(pitchSemitones, forKey: Keys.pitchSemitones); changed() }
    }
    /// Low-shelf gain in dB.
    public var bassDb: Double {
        didSet { defaults.set(bassDb, forKey: Keys.bassDb); changed() }
    }
    /// High-shelf gain in dB.
    public var trebleDb: Double {
        didSet { defaults.set(trebleDb, forKey: Keys.trebleDb); changed() }
    }
    public var ignoreAutorepeat: Bool {
        didSet { defaults.set(ignoreAutorepeat, forKey: Keys.ignoreAutorepeat); changed() }
    }
    /// Adds an interaural time difference for headphones.
    public var headphoneMode: Bool {
        didSet { defaults.set(headphoneMode, forKey: Keys.headphoneMode); changed() }
    }
    public var keyboardLayout: KeyboardLayoutKind {
        didSet { defaults.set(keyboardLayout.rawValue, forKey: Keys.keyboardLayout); changed() }
    }
    /// Manual pause.
    public var paused: Bool {
        didSet { defaults.set(paused, forKey: Keys.paused); changed() }
    }
    public var excludedBundleIDs: [String] {
        didSet { defaults.set(excludedBundleIDs, forKey: Keys.excludedBundleIDs); changed() }
    }
    public var pauseForGames: Bool {
        didSet { defaults.set(pauseForGames, forKey: Keys.pauseForGames); changed() }
    }
    public var pauseInFullscreen: Bool {
        didSet { defaults.set(pauseInFullscreen, forKey: Keys.pauseInFullscreen); changed() }
    }
    public var pauseOnSecureInput: Bool {
        didSet { defaults.set(pauseOnSecureInput, forKey: Keys.pauseOnSecureInput); changed() }
    }
    public var hotkeyEnabled: Bool {
        didSet { defaults.set(hotkeyEnabled, forKey: Keys.hotkeyEnabled); changed() }
    }

    /// Receives `volume²` whenever the volume changes.
    @ObservationIgnored public weak var mixer: VoiceMixer? {
        didSet { pushGain() }
    }
    /// Called after any setting changes.
    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.volume: 0.8,
            Keys.spatialWidth: 0.7,
            Keys.pitchVariance: Defaults.pitchVariance,
            Keys.volumeVarianceDb: Defaults.volumeVarianceDb,
            Keys.upGainDb: Defaults.upGainDb,
            Keys.pitchSemitones: Defaults.pitchSemitones,
            Keys.bassDb: Defaults.bassDb,
            Keys.trebleDb: Defaults.trebleDb,
            Keys.ignoreAutorepeat: true,
            Keys.headphoneMode: false,
            Keys.keyboardLayout: KeyboardLayoutKind.detectSystem().rawValue,
            Keys.paused: false,
            Keys.excludedBundleIDs: [String](),
            Keys.pauseForGames: true,
            Keys.pauseInFullscreen: false,
            Keys.pauseOnSecureInput: true,
            Keys.hotkeyEnabled: true,
        ])
        volume = min(max(defaults.double(forKey: Keys.volume), 0), 1)
        selectedTheme = defaults.string(forKey: Keys.selectedTheme)
        spatialWidth = defaults.double(forKey: Keys.spatialWidth)
        pitchVariance = defaults.double(forKey: Keys.pitchVariance)
        volumeVarianceDb = defaults.double(forKey: Keys.volumeVarianceDb)
        upGainDb = defaults.double(forKey: Keys.upGainDb)
        pitchSemitones = defaults.double(forKey: Keys.pitchSemitones)
        bassDb = defaults.double(forKey: Keys.bassDb)
        trebleDb = defaults.double(forKey: Keys.trebleDb)
        ignoreAutorepeat = defaults.bool(forKey: Keys.ignoreAutorepeat)
        headphoneMode = defaults.bool(forKey: Keys.headphoneMode)
        keyboardLayout = KeyboardLayoutKind(rawValue: defaults.string(forKey: Keys.keyboardLayout) ?? "") ?? .ansi
        paused = defaults.bool(forKey: Keys.paused)
        excludedBundleIDs = defaults.stringArray(forKey: Keys.excludedBundleIDs) ?? []
        pauseForGames = defaults.bool(forKey: Keys.pauseForGames)
        pauseInFullscreen = defaults.bool(forKey: Keys.pauseInFullscreen)
        pauseOnSecureInput = defaults.bool(forKey: Keys.pauseOnSecureInput)
        hotkeyEnabled = defaults.bool(forKey: Keys.hotkeyEnabled)
    }

    public func resetVariation() {
        pitchVariance = Defaults.pitchVariance
        volumeVarianceDb = Defaults.volumeVarianceDb
        upGainDb = Defaults.upGainDb
    }

    public func resetTone() {
        pitchSemitones = Defaults.pitchSemitones
        bassDb = Defaults.bassDb
        trebleDb = Defaults.trebleDb
    }

    public var masterGain: Float {
        let v = Float(min(max(volume, 0), 1))
        return v * v
    }

    private func pushGain() {
        mixer?.setMasterGain(masterGain)
    }

    private func changed() {
        onChange?()
    }
}
