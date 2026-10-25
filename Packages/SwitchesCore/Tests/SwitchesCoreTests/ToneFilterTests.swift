import Foundation
import Testing
@testable import SwitchesCore

struct ToneFilterTests {
    /// Steady-state amplitude of a sine at `frequency` after the filter.
    private func gain(of filter: ToneFilter, at frequency: Double, sampleRate: Double = 48_000) -> Double {
        var f = filter
        var sum = 0.0
        let n = Int(sampleRate / 2)
        for i in 0..<n {
            let y = f.process(Float(sin(2 * Double.pi * frequency * Double(i) / sampleRate)))
            if i >= n / 2 { sum += Double(y * y) }
        }
        // RMS of a unit sine is 1/√2.
        return (sum / Double(n - n / 2)).squareRoot() * 2.0.squareRoot()
    }

    private func db(_ g: Double) -> Double { 20 * log10(g) }

    @Test func flatAtZeroGain() {
        var f = ToneFilter()
        f.configure(bassDb: 0, trebleDb: 0, sampleRate: 48_000)
        for freq in [50.0, 1_000, 10_000] {
            #expect(abs(db(gain(of: f, at: freq))) < 0.1)
        }
    }

    @Test func bassBoostsLowsOnly() {
        var f = ToneFilter()
        f.configure(bassDb: 6, trebleDb: 0, sampleRate: 48_000)
        #expect(abs(db(gain(of: f, at: 30)) - 6) < 0.5)
        #expect(abs(db(gain(of: f, at: 10_000))) < 0.5)
    }

    @Test func trebleCutsHighsOnly() {
        var f = ToneFilter()
        f.configure(bassDb: 0, trebleDb: -6, sampleRate: 48_000)
        #expect(abs(db(gain(of: f, at: 16_000)) + 6) < 0.5)
        #expect(abs(db(gain(of: f, at: 50))) < 0.5)
    }
}
