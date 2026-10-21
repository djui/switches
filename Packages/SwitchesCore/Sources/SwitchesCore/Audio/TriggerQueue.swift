import Synchronization

/// A request to start one voice. Built off the audio thread, consumed by `VoiceMixer`.
public struct Trigger: @unchecked Sendable {
    /// Mono float samples owned by a `SampleBank` that outlives the trigger's generation.
    public var samples: UnsafePointer<Float>
    public var frameCount: Int32
    /// Source sample rate multiplied by the pitch ratio, in Hz.
    public var sourceRate: Float
    public var gain: Float
    /// -1 (left) ... 1 (right).
    public var pan: Float
    /// Triggers whose generation differs from the mixer's current one are discarded.
    public var generation: UInt32

    public init(
        samples: UnsafePointer<Float>,
        frameCount: Int32,
        sourceRate: Float,
        gain: Float,
        pan: Float,
        generation: UInt32
    ) {
        self.samples = samples
        self.frameCount = frameCount
        self.sourceRate = sourceRate
        self.gain = gain
        self.pan = pan
        self.generation = generation
    }
}

/// Lock-free single-producer / single-consumer ring buffer of `Trigger`s.
///
/// Exactly one thread may call `push` and exactly one thread may call `pop` at a time.
/// Neither operation allocates or locks, so `pop` is safe on the real-time audio thread.
public final class TriggerQueue: @unchecked Sendable {
    public let capacity: Int
    private let mask: Int
    private let storage: UnsafeMutablePointer<Trigger>
    private let head = Atomic<Int>(0)
    private let tail = Atomic<Int>(0)

    public init(capacity: Int = 256) {
        var size = 2
        while size < capacity { size <<= 1 }
        self.capacity = size
        self.mask = size - 1
        self.storage = .allocate(capacity: size)
    }

    deinit {
        storage.deallocate()
    }

    /// Returns `false` when the queue is full and the trigger was dropped.
    @discardableResult
    public func push(_ trigger: Trigger) -> Bool {
        let h = head.load(ordering: .relaxed)
        let t = tail.load(ordering: .acquiring)
        if h &- t >= capacity { return false }
        (storage + (h & mask)).initialize(to: trigger)
        head.store(h &+ 1, ordering: .releasing)
        return true
    }

    public func pop() -> Trigger? {
        let t = tail.load(ordering: .relaxed)
        let h = head.load(ordering: .acquiring)
        if t == h { return nil }
        let trigger = storage[t & mask]
        tail.store(t &+ 1, ordering: .releasing)
        return trigger
    }

    public var count: Int {
        head.load(ordering: .acquiring) &- tail.load(ordering: .acquiring)
    }
}
