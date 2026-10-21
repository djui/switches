import Foundation
import Observation
import Synchronization

/// Turns key events into voice triggers. Runs on the key-tap thread; the mutex is only
/// contended briefly when settings or the theme change on the main thread.
final class TriggerPipeline: Sendable {
    struct Config {
        var pack: ThemePack?
        var generation: UInt32 = 0
        var layout = KeyLayout()
        var spatialWidth: Float = 0.7
        var pitchVariance: Float = 0.03
        var volumeVarianceDb: Float = 1.5
        var upGain: Float = 0.63
        var ignoreAutorepeat = true
        var rng = SplitMix64(seed: UInt64.random(in: .min ... .max))
    }

    let config = Mutex(Config())
    let gate: PauseGate
    let mixer: VoiceMixer

    init(gate: PauseGate, mixer: VoiceMixer) {
        self.gate = gate
        self.mixer = mixer
    }

    func handle(_ event: KeyEvent, bypassPause: Bool = false) {
        if !bypassPause, gate.shouldDrop() { return }
        let queue = mixer.queue
        config.withLock { c in
            if event.isRepeat, c.ignoreAutorepeat { return }
            guard let pack = c.pack else { return }
            let info = c.layout.info(for: event.keyCode)
            guard let sample = pack.sample(for: event.keyCode, group: info.group, isDown: event.isDown) else { return }

            let pitchRange = max(c.pitchVariance, 0)
            let gainRange = max(c.volumeVarianceDb, 0)
            let pitch = 1 + Float.random(in: -pitchRange...pitchRange, using: &c.rng)
            let db = Float.random(in: -gainRange...gainRange, using: &c.rng)
            var gain = powf(10, db / 20)
            if !event.isDown { gain *= c.upGain }

            // Called under the lock, so there is exactly one producer for the SPSC queue.
            queue.push(Trigger(
                samples: sample.pointer,
                frameCount: Int32(clamping: sample.count),
                sourceRate: Float(sample.sampleRate) * pitch,
                gain: gain,
                pan: info.pan * c.spatialWidth,
                generation: c.generation
            ))
        }
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Wires KeyEventTap → PauseController → trigger pipeline → AudioEngine, and loads themes.
@MainActor
@Observable
public final class EngineController {
    public let appState: AppState
    public let permissions = PermissionManager()
    public let pause: PauseController
    public let launchAtLogin = LaunchAtLogin()

    public private(set) var themeNames: [String] = []
    public private(set) var loadedThemeName: String?
    public private(set) var isLoadingTheme = false
    public private(set) var isListening = false
    public private(set) var lastError: String?

    @ObservationIgnored private let mixer = VoiceMixer()
    @ObservationIgnored private let audio: AudioEngine
    @ObservationIgnored private let pipeline: TriggerPipeline
    @ObservationIgnored private let packStore: PackStore
    @ObservationIgnored private var tap: KeyEventTap?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var retiredPacks: [ThemePack] = []
    @ObservationIgnored private var requestedThemeName: String?
    @ObservationIgnored private var themeLoadTask: Task<Void, Never>?
    @ObservationIgnored private var layoutKind: KeyboardLayoutKind?
    @ObservationIgnored private var started = false

    public init(appState: AppState, packStore: PackStore = .bundled()) {
        self.appState = appState
        self.packStore = packStore
        self.pause = PauseController(appState: appState)
        self.audio = AudioEngine(mixer: mixer)
        self.pipeline = TriggerPipeline(gate: pause.gate, mixer: mixer)
    }

    /// Sounds play only when all of these hold.
    public var isActive: Bool {
        isListening && !pause.isPaused && loadedThemeName != nil
    }

    public var statusText: String {
        if !permissions.isGranted { return "Needs Input Monitoring permission" }
        if let reason = pause.reason { return reason.description }
        if isLoadingTheme { return "Loading theme…" }
        if let lastError { return lastError }
        return isListening ? "Active" : "Starting…"
    }

    public func start() {
        guard !started else { return }
        started = true
        appState.mixer = mixer
        appState.onChange = { [weak self] in self?.settingsChanged() }
        themeNames = packStore.themeNames()
        applySettings()
        audio.start()
        if let error = audio.lastError { lastError = "Audio: \(error)" }
        pause.start()
        loadSelectedTheme()
        startListening()
    }

    public func stop() {
        tap?.stop()
        tap = nil
        permissionTimer?.invalidate()
        permissionTimer = nil
        audio.stop()
        pause.stop()
        isListening = false
        started = false
    }

    /// Starts the key tap now if Input Monitoring is granted, otherwise polls until it is.
    public func startListening() {
        if tap == nil {
            let pipeline = self.pipeline
            tap = KeyEventTap { pipeline.handle($0) }
        }
        if permissions.refresh(), tap?.start() == true {
            isListening = true
            permissionTimer?.invalidate()
            permissionTimer = nil
            return
        }
        isListening = false
        guard permissionTimer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.startListening() }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    /// Plays a key-down then key-up of the "A" key, ignoring pause state.
    public func playPreview() {
        let pipeline = self.pipeline
        pipeline.handle(KeyEvent(keyCode: 0, isDown: true), bypassPause: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            pipeline.handle(KeyEvent(keyCode: 0, isDown: false), bypassPause: true)
        }
    }

    // MARK: Settings

    private func settingsChanged() {
        applySettings()
        pause.settingsChanged()
        if resolvedThemeName() != requestedThemeName {
            loadSelectedTheme()
        }
    }

    private func applySettings() {
        mixer.setMasterGain(appState.masterGain)
        mixer.setHeadphoneMode(appState.headphoneMode)

        let kind = appState.keyboardLayout
        let layout: KeyLayout? = kind == layoutKind ? nil : KeyLayout(kind: kind)
        layoutKind = kind
        let spatialWidth = Float(min(max(appState.spatialWidth, 0), 1))
        let pitchVariance = Float(min(max(appState.pitchVariance, 0), 0.25))
        let volumeVarianceDb = Float(min(max(appState.volumeVarianceDb, 0), 12))
        let upGain = powf(10, Float(appState.upGainDb) / 20)
        let ignoreAutorepeat = appState.ignoreAutorepeat
        pipeline.config.withLock { c in
            if let layout { c.layout = layout }
            c.spatialWidth = spatialWidth
            c.pitchVariance = pitchVariance
            c.volumeVarianceDb = volumeVarianceDb
            c.upGain = upGain
            c.ignoreAutorepeat = ignoreAutorepeat
        }
    }

    // MARK: Themes

    private func resolvedThemeName() -> String? {
        if let selected = appState.selectedTheme, themeNames.contains(selected) { return selected }
        return themeNames.first
    }

    private func loadSelectedTheme() {
        guard let name = resolvedThemeName() else {
            lastError = "No themes found in the app bundle"
            return
        }
        let isInitialLoad = requestedThemeName == nil
        requestedThemeName = name
        if appState.selectedTheme != name { appState.selectedTheme = name }

        themeLoadTask?.cancel()
        isLoadingTheme = true
        let store = packStore
        themeLoadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result { try store.loadTheme(named: name) }
            }.value
            guard let self, !Task.isCancelled, self.requestedThemeName == name else { return }
            self.isLoadingTheme = false
            switch result {
            case let .success(pack):
                self.install(pack)
                if !isInitialLoad { self.playPreview() }
            case let .failure(error):
                self.lastError = "Theme \(name): \(error.localizedDescription)"
            }
        }
    }

    private func install(_ pack: ThemePack) {
        let generation = mixer.advanceGeneration()
        let old = pipeline.config.withLock { c -> ThemePack? in
            let old = c.pack
            c.pack = pack
            c.generation = generation
            return old
        }
        loadedThemeName = pack.name
        lastError = nil
        guard let old else { return }
        // Voices from the old generation are dropped on the next render cycle; keep the
        // sample memory alive well past that before freeing it off the audio thread.
        retiredPacks.append(old)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated {
                self?.retiredPacks.removeAll { $0 === old }
            }
        }
    }
}
