import AVFoundation
import Foundation

public struct SampleBuffer: @unchecked Sendable {
    public let pointer: UnsafePointer<Float>
    public let count: Int
    public let sampleRate: Double
}

public enum SampleBankError: Error, LocalizedError {
    case unreadable(URL, String)
    case empty(URL)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(url, reason): "Cannot read \(url.lastPathComponent): \(reason)"
        case let .empty(url): "\(url.lastPathComponent) contains no audio"
        }
    }
}

/// Immutable set of mono 48 kHz float sample buffers.
///
/// Buffers are allocated once at load time and freed when the bank is released, so the
/// audio thread can read them through raw pointers while the bank is kept alive.
public final class SampleBank: @unchecked Sendable {
    public static let sampleRate = 48_000.0

    public let buffers: [SampleBuffer]

    public init(urls: [URL]) throws {
        var loaded: [SampleBuffer] = []
        loaded.reserveCapacity(urls.count)
        do {
            for url in urls { loaded.append(try Self.load(url)) }
        } catch {
            for buffer in loaded { UnsafeMutablePointer(mutating: buffer.pointer).deallocate() }
            throw error
        }
        buffers = loaded
    }

    deinit {
        for buffer in buffers { UnsafeMutablePointer(mutating: buffer.pointer).deallocate() }
    }

    public var totalFrames: Int { buffers.reduce(0) { $0 + $1.count } }

    static func load(_ url: URL) throws -> SampleBuffer {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw SampleBankError.unreadable(url, error.localizedDescription)
        }
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw SampleBankError.empty(url)
        }
        do {
            try file.read(into: pcm)
        } catch {
            throw SampleBankError.unreadable(url, error.localizedDescription)
        }
        guard let channels = pcm.floatChannelData, pcm.frameLength > 0 else { throw SampleBankError.empty(url) }

        let count = Int(pcm.frameLength)
        let channelCount = Int(format.channelCount)
        var mono = [Float](repeating: 0, count: count)
        for c in 0..<channelCount {
            let p = channels[c]
            for i in 0..<count { mono[i] += p[i] }
        }
        if channelCount > 1 {
            let scale = 1 / Float(channelCount)
            for i in 0..<count { mono[i] *= scale }
        }
        if format.sampleRate != sampleRate {
            mono = try resample(mono, from: format.sampleRate, url: url)
        }
        guard !mono.isEmpty else { throw SampleBankError.empty(url) }

        let storage = UnsafeMutablePointer<Float>.allocate(capacity: mono.count)
        storage.initialize(from: mono, count: mono.count)
        return SampleBuffer(pointer: UnsafePointer(storage), count: mono.count, sampleRate: sampleRate)
    }

    private static func resample(_ input: [Float], from rate: Double, url: URL) throws -> [Float] {
        guard
            let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
            let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inFormat, to: outFormat),
            let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(input.count))
        else { throw SampleBankError.unreadable(url, "unsupported sample rate \(rate)") }

        converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        inBuffer.frameLength = AVAudioFrameCount(input.count)
        inBuffer.floatChannelData![0].update(from: input, count: input.count)

        let capacity = AVAudioFrameCount(Double(input.count) * sampleRate / rate) + 1024
        guard let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else {
            throw SampleBankError.unreadable(url, "cannot allocate resample buffer")
        }
        nonisolated(unsafe) var supplied = false
        var conversionError: NSError?
        converter.convert(to: outBuffer, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return inBuffer
        }
        if let conversionError { throw SampleBankError.unreadable(url, conversionError.localizedDescription) }
        return Array(UnsafeBufferPointer(start: outBuffer.floatChannelData![0], count: Int(outBuffer.frameLength)))
    }
}
