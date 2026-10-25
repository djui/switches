import Darwin

/// Transposed direct form II biquad. Coefficients are normalized so `a0 == 1`.
struct Biquad {
    var b0: Float = 1
    var b1: Float = 0
    var b2: Float = 0
    var a1: Float = 0
    var a2: Float = 0
    private var z1: Float = 0
    private var z2: Float = 0

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    mutating func reset() {
        z1 = 0
        z2 = 0
    }

    /// RBJ cookbook shelf (slope 1). Keeps the filter state so retuning doesn't click.
    mutating func setShelf(high: Bool, gainDb: Double, frequency: Double, sampleRate: Double) {
        let a = pow(10, gainDb / 40)
        let w0 = 2 * Double.pi * min(frequency, sampleRate * 0.45) / sampleRate
        let cosW = cos(w0)
        let alpha = sin(w0) / 2 * 2.0.squareRoot()
        let k = 2 * a.squareRoot() * alpha
        let s: Double = high ? -1 : 1

        let nb0 = a * ((a + 1) - s * (a - 1) * cosW + k)
        let nb1 = s * 2 * a * ((a - 1) - s * (a + 1) * cosW)
        let nb2 = a * ((a + 1) - s * (a - 1) * cosW - k)
        let na0 = (a + 1) + s * (a - 1) * cosW + k
        let na1 = -s * 2 * ((a - 1) + s * (a + 1) * cosW)
        let na2 = (a + 1) + s * (a - 1) * cosW - k

        b0 = Float(nb0 / na0)
        b1 = Float(nb1 / na0)
        b2 = Float(nb2 / na0)
        a1 = Float(na1 / na0)
        a2 = Float(na2 / na0)
    }
}

/// Bass (low shelf) and treble (high shelf) tone control for one channel.
struct ToneFilter {
    static let bassFrequency = 250.0
    static let trebleFrequency = 4_000.0

    private var bass = Biquad()
    private var treble = Biquad()

    @inline(__always)
    mutating func process(_ x: Float) -> Float {
        treble.process(bass.process(x))
    }

    mutating func reset() {
        bass.reset()
        treble.reset()
    }

    mutating func configure(bassDb: Double, trebleDb: Double, sampleRate: Double) {
        bass.setShelf(high: false, gainDb: bassDb, frequency: Self.bassFrequency, sampleRate: sampleRate)
        treble.setShelf(high: true, gainDb: trebleDb, frequency: Self.trebleFrequency, sampleRate: sampleRate)
    }
}
