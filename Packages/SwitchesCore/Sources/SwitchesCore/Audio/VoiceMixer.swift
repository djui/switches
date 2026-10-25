import Darwin
import Synchronization

/// Fixed-size polyphonic sample player that renders on the real-time audio thread.
///
/// `render` never allocates, locks, or touches reference counts of shared objects; all
/// cross-thread communication goes through `TriggerQueue` and atomics.
public final class VoiceMixer: @unchecked Sendable {
    public static let maxVoices = 32
    /// Largest interaural time difference applied in headphone mode (~0.66 ms).
    static let maxITDSeconds = 0.00066

    struct Voice {
        var active = false
        var samples: UnsafePointer<Float>?
        var length = 0
        var position = 0.0
        var step = 1.0
        var gainL: Float = 0
        var gainR: Float = 0
        var delayL = 0.0
        var delayR = 0.0
        var age: UInt64 = 0
    }

    public let queue: TriggerQueue
    private let voices: UnsafeMutablePointer<Voice>
    private let targetGainBits = Atomic<UInt32>(Float(0.64).bitPattern)
    private let generation = Atomic<UInt32>(0)
    private let headphoneMode = Atomic<Bool>(false)
    private let bassDbBits = Atomic<UInt32>(Float(0).bitPattern)
    private let trebleDbBits = Atomic<UInt32>(Float(0).bitPattern)

    // Audio-thread state. `outputSampleRate` and `smoothing` change only while not rendering.
    private var currentGain: Float = 0.64
    private var seenGeneration: UInt32 = 0
    private var ageCounter: UInt64 = 0
    private var outputSampleRate = 48_000.0
    private var smoothing: Float = 0
    private var toneL = ToneFilter()
    private var toneR = ToneFilter()
    private var appliedBassDb: Float = 0
    private var appliedTrebleDb: Float = 0
    private var toneActive = false

    public init(queueCapacity: Int = 256) {
        queue = TriggerQueue(capacity: queueCapacity)
        voices = .allocate(capacity: Self.maxVoices)
        voices.initialize(repeating: Voice(), count: Self.maxVoices)
        prepare(sampleRate: 48_000)
    }

    deinit {
        voices.deinitialize(count: Self.maxVoices)
        voices.deallocate()
    }

    // MARK: Control (any thread)

    /// Linear master gain, smoothed over ~10 ms on the audio thread.
    public func setMasterGain(_ gain: Float) {
        targetGainBits.store(max(0, gain).bitPattern, ordering: .relaxed)
    }

    public var masterGain: Float {
        Float(bitPattern: targetGainBits.load(ordering: .relaxed))
    }

    public func setHeadphoneMode(_ enabled: Bool) {
        headphoneMode.store(enabled, ordering: .relaxed)
    }

    /// Low-shelf (bass) and high-shelf (treble) gain in dB; 0 bypasses the filter.
    public func setTone(bassDb: Float, trebleDb: Float) {
        bassDbBits.store(bassDb.bitPattern, ordering: .relaxed)
        trebleDbBits.store(trebleDb.bitPattern, ordering: .relaxed)
    }

    /// Invalidates all playing voices and queued triggers (used when swapping sample banks).
    @discardableResult
    public func advanceGeneration() -> UInt32 {
        generation.add(1, ordering: .acquiringAndReleasing).newValue
    }

    public var currentGeneration: UInt32 {
        generation.load(ordering: .acquiring)
    }

    /// Must only be called while the audio engine is not rendering.
    public func prepare(sampleRate: Double) {
        outputSampleRate = sampleRate > 0 ? sampleRate : 48_000
        smoothing = Float(1 - exp(-1 / (0.010 * outputSampleRate)))
        for i in 0..<Self.maxVoices { voices[i].active = false }
        configureTone(bassDb: appliedBassDb, trebleDb: appliedTrebleDb)
        toneL.reset()
        toneR.reset()
    }

    private func configureTone(bassDb: Float, trebleDb: Float) {
        appliedBassDb = bassDb
        appliedTrebleDb = trebleDb
        toneActive = bassDb != 0 || trebleDb != 0
        toneL.configure(bassDb: Double(bassDb), trebleDb: Double(trebleDb), sampleRate: outputSampleRate)
        toneR.configure(bassDb: Double(bassDb), trebleDb: Double(trebleDb), sampleRate: outputSampleRate)
    }

    // MARK: Render (audio thread)

    /// Renders `frameCount` frames into the (non-interleaved) output buffers.
    /// Returns `false` when the output is silent.
    public func render(
        frameCount: Int,
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>?
    ) -> Bool {
        let gen = generation.load(ordering: .acquiring)
        if gen != seenGeneration {
            for i in 0..<Self.maxVoices { voices[i].active = false }
            seenGeneration = gen
        }
        while let trigger = queue.pop() {
            if trigger.generation == gen { start(trigger) }
        }

        left.update(repeating: 0, count: frameCount)
        right?.update(repeating: 0, count: frameCount)
        let r = right ?? left

        var activeCount = 0
        for i in 0..<Self.maxVoices where voices[i].active {
            activeCount += 1
            mix(voices + i, left, r, frameCount)
        }

        let bassDb = Float(bitPattern: bassDbBits.load(ordering: .relaxed))
        let trebleDb = Float(bitPattern: trebleDbBits.load(ordering: .relaxed))
        if bassDb != appliedBassDb || trebleDb != appliedTrebleDb {
            configureTone(bassDb: bassDb, trebleDb: trebleDb)
        }

        let target = Float(bitPattern: targetGainBits.load(ordering: .relaxed))
        if activeCount == 0 {
            currentGain = target
            toneL.reset()
            toneR.reset()
            return false
        }

        if toneActive {
            for i in 0..<frameCount {
                left[i] = toneL.process(left[i])
                if let right { right[i] = toneR.process(right[i]) }
            }
        }

        var g = currentGain
        let a = smoothing
        for i in 0..<frameCount {
            g += (target - g) * a
            left[i] = Self.softLimit(left[i] * g)
            if let right { right[i] = Self.softLimit(right[i] * g) }
        }
        currentGain = g
        return true
    }

    private func start(_ t: Trigger) {
        guard t.frameCount > 1, t.sourceRate > 0 else { return }

        var slot = -1
        var oldest = UInt64.max
        for i in 0..<Self.maxVoices {
            if !voices[i].active { slot = i; break }
            if voices[i].age < oldest { oldest = voices[i].age; slot = i }
        }

        let pan = min(max(t.pan, -1), 1)
        let angle = (pan + 1) * (Float.pi / 4)
        var delayL = 0.0
        var delayR = 0.0
        if headphoneMode.load(ordering: .relaxed) {
            let delay = Double(abs(pan)) * Self.maxITDSeconds * outputSampleRate
            if pan > 0 { delayL = delay } else { delayR = delay }
        }

        ageCounter &+= 1
        voices[slot] = Voice(
            active: true,
            samples: t.samples,
            length: Int(t.frameCount),
            position: 0,
            step: Double(t.sourceRate) / outputSampleRate,
            gainL: cos(angle) * t.gain,
            gainR: sin(angle) * t.gain,
            delayL: delayL,
            delayR: delayR,
            age: ageCounter
        )
    }

    @inline(__always)
    private func mix(
        _ v: UnsafeMutablePointer<Voice>,
        _ left: UnsafeMutablePointer<Float>,
        _ right: UnsafeMutablePointer<Float>,
        _ frameCount: Int
    ) {
        guard let samples = v.pointee.samples else {
            v.pointee.active = false
            return
        }
        let last = v.pointee.length - 1
        let step = v.pointee.step
        let dL = v.pointee.delayL
        let dR = v.pointee.delayR
        let gL = v.pointee.gainL
        let gR = v.pointee.gainR
        let end = Double(last) + max(dL, dR)
        var pos = v.pointee.position

        for i in 0..<frameCount {
            if pos >= end {
                v.pointee.active = false
                break
            }
            left[i] += Self.read(samples, last, pos - dL) * gL
            right[i] += Self.read(samples, last, pos - dR) * gR
            pos += step
        }
        v.pointee.position = pos
    }

    @inline(__always)
    static func read(_ s: UnsafePointer<Float>, _ last: Int, _ p: Double) -> Float {
        if p < 0 { return 0 }
        let i = Int(p)
        if i >= last { return i == last ? s[last] : 0 }
        let a = s[i]
        return a + (s[i + 1] - a) * Float(p - Double(i))
    }

    /// Transparent below 0.8, tanh knee above, never exceeds ±1.
    @inline(__always)
    static func softLimit(_ x: Float) -> Float {
        let threshold: Float = 0.8
        let magnitude = abs(x)
        if magnitude <= threshold { return x }
        let y = threshold + (1 - threshold) * tanhf((magnitude - threshold) / (1 - threshold))
        return x < 0 ? -y : y
    }
}
