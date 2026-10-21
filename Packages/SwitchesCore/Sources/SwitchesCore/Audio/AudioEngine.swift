import AVFoundation
import CoreAudio
import Foundation

/// Owns the `AVAudioEngine` graph: one `AVAudioSourceNode` driven by `VoiceMixer`.
///
/// The graph is rebuilt from scratch whenever the output device or its format changes.
@MainActor
public final class AudioEngine {
    public let mixer: VoiceMixer
    /// Requested I/O buffer size; 64–128 frames keeps output latency around 1.5–3 ms.
    public var preferredBufferFrames: UInt32 = 96

    public private(set) var isRunning = false
    public private(set) var outputSampleRate: Double = 0
    public private(set) var lastError: String?

    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var rebuildScheduled = false

    public init(mixer: VoiceMixer) {
        self.mixer = mixer
    }

    public func start() {
        installDeviceListener()
        rebuild()
    }

    public func stop() {
        removeDeviceListener()
        teardown()
    }

    private func rebuild() {
        teardown()
        let engine = AVAudioEngine()
        let hardwareFormat = engine.outputNode.outputFormat(forBus: 0)
        let rate = hardwareFormat.sampleRate > 0 ? hardwareFormat.sampleRate : SampleBank.sampleRate
        mixer.prepare(sampleRate: rate)

        guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else {
            lastError = "Unsupported output format"
            return
        }
        let node = Self.makeSourceNode(format: format, mixer: mixer)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1
        applyBufferSize(engine)

        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRebuild() }
        }

        engine.prepare()
        do {
            try engine.start()
            self.engine = engine
            isRunning = true
            outputSampleRate = rate
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
            configurationObserver = nil
        }
    }

    private func teardown() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
        configurationObserver = nil
        engine?.stop()
        engine = nil
        isRunning = false
    }

    private func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.rebuildScheduled = false
                self.rebuild()
            }
        }
    }

    private func applyBufferSize(_ engine: AVAudioEngine) {
        guard let unit = engine.outputNode.audioUnit else { return }
        var frames = min(max(preferredBufferFrames, 64), 128)
        AudioUnitSetProperty(
            unit,
            kAudioDevicePropertyBufferFrameSize,
            kAudioUnitScope_Global,
            0,
            &frames,
            UInt32(MemoryLayout<UInt32>.size)
        )
    }

    // MARK: Default output device

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private func installDeviceListener() {
        guard deviceListener == nil else { return }
        let listener = Self.makeDeviceListener { [weak self] in
            self?.scheduleRebuild()
        }
        var address = Self.defaultOutputAddress
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, listener
        )
        if status == noErr { deviceListener = listener }
    }

    private func removeDeviceListener() {
        guard let deviceListener else { return }
        var address = Self.defaultOutputAddress
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, deviceListener
        )
        self.deviceListener = nil
    }

    // Built outside the main actor so the closures carry no main-actor isolation checks.

    nonisolated private static func makeDeviceListener(
        _ onChange: @escaping @MainActor () -> Void
    ) -> AudioObjectPropertyListenerBlock {
        { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    nonisolated private static func makeSourceNode(format: AVAudioFormat, mixer: VoiceMixer) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { isSilence, _, frameCount, audioBufferList -> OSStatus in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard
                buffers.count > 0,
                let left = buffers[0].mData?.assumingMemoryBound(to: Float.self)
            else { return noErr }
            let right = buffers.count > 1 ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil
            if !mixer.render(frameCount: Int(frameCount), left: left, right: right) {
                isSilence.pointee = true
            }
            return noErr
        }
    }
}
