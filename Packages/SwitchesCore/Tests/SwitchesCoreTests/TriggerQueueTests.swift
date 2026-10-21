import Foundation
import Testing
@testable import SwitchesCore

struct TriggerQueueTests {
    nonisolated(unsafe) private static let silence: UnsafeMutablePointer<Float> = {
        let p = UnsafeMutablePointer<Float>.allocate(capacity: 4)
        p.initialize(repeating: 0, count: 4)
        return p
    }()

    private func trigger(_ n: Int) -> Trigger {
        Trigger(samples: Self.silence, frameCount: 4, sourceRate: 48_000, gain: Float(n), pan: 0, generation: 0)
    }

    @Test func capacityRoundsUpToPowerOfTwo() {
        #expect(TriggerQueue(capacity: 100).capacity == 128)
        #expect(TriggerQueue(capacity: 1).capacity == 2)
    }

    @Test func fifoOrder() {
        let queue = TriggerQueue(capacity: 8)
        for i in 0..<5 { #expect(queue.push(trigger(i))) }
        #expect(queue.count == 5)
        for i in 0..<5 { #expect(queue.pop()?.gain == Float(i)) }
        #expect(queue.pop() == nil)
    }

    @Test func rejectsWhenFullAndRecovers() {
        let queue = TriggerQueue(capacity: 4)
        for i in 0..<4 { #expect(queue.push(trigger(i))) }
        #expect(!queue.push(trigger(99)))
        #expect(queue.pop()?.gain == 0)
        #expect(queue.push(trigger(4)))
        let rest = (0..<4).compactMap { _ in queue.pop()?.gain }
        #expect(rest == [1, 2, 3, 4])
    }

    @Test func concurrentProducerConsumerKeepsOrder() async {
        let queue = TriggerQueue(capacity: 64)
        let total = 50_000
        let producer = Thread {
            var i = 0
            while i < total {
                if queue.push(Trigger(samples: Self.silence, frameCount: 4, sourceRate: 1, gain: Float(i), pan: 0, generation: 0)) {
                    i += 1
                }
            }
        }
        producer.start()
        var expected = 0
        var ordered = true
        while expected < total {
            if let t = queue.pop() {
                if t.gain != Float(expected) { ordered = false }
                expected += 1
            }
        }
        #expect(ordered)
        #expect(queue.pop() == nil)
    }

    @Test func mixerRendersQueuedTrigger() {
        let mixer = VoiceMixer()
        let samples = UnsafeMutablePointer<Float>.allocate(capacity: 256)
        defer { samples.deallocate() }
        samples.initialize(repeating: 0.5, count: 256)
        mixer.setMasterGain(1)
        mixer.queue.push(Trigger(samples: samples, frameCount: 256, sourceRate: 48_000, gain: 1, pan: -1, generation: 0))

        var left = [Float](repeating: 0, count: 64)
        var right = [Float](repeating: 0, count: 64)
        let active = left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in
                mixer.render(frameCount: 64, left: l.baseAddress!, right: r.baseAddress!)
            }
        }
        #expect(active)
        // Master gain ramps from its initial 0.64 towards 1 over ~10 ms.
        #expect(left[10] > 0.3)
        #expect(abs(right[10]) < 0.001)
    }

    @Test func mixerDropsStaleGeneration() {
        let mixer = VoiceMixer()
        mixer.queue.push(trigger(1))
        mixer.advanceGeneration()
        var left = [Float](repeating: 0, count: 16)
        let active = left.withUnsafeMutableBufferPointer { l in
            mixer.render(frameCount: 16, left: l.baseAddress!, right: nil)
        }
        #expect(!active)
    }
}
