#!/usr/bin/env swift
// Converts raw sound packs in Sounds/ into runtime themes in Switches/Resources/Themes/.
//
// Usage (from the repo root): swift scripts/convert_sounds.swift
//
// Input formats:
//   * Per-key WAV:       Sounds/<Pack>/{mechvibesID}-down.wav, {mechvibesID}-up.wav
//   * Mechvibes single:  Sounds/<Pack>/config.json + sound file sliced by `defines`
// Output per theme:      theme.json + {cgKeyCode}-down.caf / {cgKeyCode}-up.caf
//                        (48 kHz, mono, 16-bit little-endian linear PCM)
//
// OGG Vorbis sources are decoded with ffmpeg (brew install ffmpeg); everything else uses
// AVFoundation. The app itself never decodes anything but CAF.

import AVFoundation
import Foundation

let targetRate = 48_000.0
let peakTarget = Float(pow(10.0, -1.0 / 20.0)) // -1 dBFS
let derivedUpGain = Float(pow(10.0, -4.0 / 20.0)) // -4 dB
let derivedUpLength = 0.6

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let soundsDir = root.appendingPathComponent("Sounds")
let themesDir = root.appendingPathComponent("Switches/Resources/Themes")
let keyMapSource = root.appendingPathComponent("Packages/SwitchesCore/Sources/SwitchesCore/Input/MechvibesKeyMap.swift")

struct ConvertError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func log(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

// MARK: - Key map (single source of truth: MechvibesKeyMap.swift)

func loadKeyMap() throws -> [Int: UInt16] {
    let text = try String(contentsOf: keyMapSource, encoding: .utf8)
    guard
        let begin = text.range(of: "// BEGIN MECHVIBES TABLE"),
        let end = text.range(of: "// END MECHVIBES TABLE")
    else { throw ConvertError("Mechvibes table markers missing in \(keyMapSource.path)") }
    var map: [Int: UInt16] = [:]
    for line in text[begin.upperBound..<end.lowerBound].split(separator: "\n") {
        let entry = line.split(separator: "//").first ?? ""
        let parts = entry.split(separator: ":").map {
            $0.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ",")))
        }
        guard parts.count == 2, let id = Int(parts[0]), let code = UInt16(parts[1]) else { continue }
        map[id] = code
    }
    guard !map.isEmpty else { throw ConvertError("Mechvibes table is empty") }
    return map
}

// Mirrors KeyLayout.group(for:) in SwitchesCore.
func group(for code: UInt16) -> String {
    switch code {
    case 49: "space"
    case 36, 76: "enter"
    case 51, 117: "backspace"
    case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63: "modifier"
    default: "alpha"
    }
}

let fallbackPreferences: [String: [UInt16]] = [
    "alpha": [0, 1, 2, 3, 37, 40, 38],
    "space": [49],
    "enter": [36, 76],
    "backspace": [51, 117],
    "modifier": [56, 60, 55, 54, 58, 59],
]

// MARK: - Decoding

func findFFmpeg() -> String? {
    let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
    if let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) { return path }
    for dir in (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":") {
        let path = "\(dir)/ffmpeg"
        if fm.isExecutableFile(atPath: path) { return path }
    }
    return nil
}

func decodeWithFFmpeg(_ url: URL) throws -> [Float] {
    guard let ffmpeg = findFFmpeg() else {
        throw ConvertError("\(url.lastPathComponent) needs ffmpeg to decode (brew install ffmpeg)")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpeg)
    process.arguments = ["-v", "error", "-i", url.path, "-f", "f32le", "-acodec", "pcm_f32le", "-ac", "1", "-ar", "48000", "-"]
    let output = Pipe()
    let errors = Pipe()
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorText = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ConvertError("ffmpeg failed on \(url.lastPathComponent): \(errorText)")
    }
    return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
}

func resample(_ input: [Float], from rate: Double) throws -> [Float] {
    guard
        let inFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false),
        let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: targetRate, channels: 1, interleaved: false),
        let converter = AVAudioConverter(from: inFormat, to: outFormat),
        let inBuffer = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(input.count)),
        let outBuffer = AVAudioPCMBuffer(
            pcmFormat: outFormat,
            frameCapacity: AVAudioFrameCount(Double(input.count) * targetRate / rate) + 1024
        )
    else { throw ConvertError("Cannot resample from \(rate) Hz") }
    converter.sampleRateConverterQuality = AVAudioQuality.max.rawValue
    inBuffer.frameLength = AVAudioFrameCount(input.count)
    inBuffer.floatChannelData![0].update(from: input, count: input.count)
    var supplied = false
    var error: NSError?
    converter.convert(to: outBuffer, error: &error) { _, status in
        if supplied {
            status.pointee = .endOfStream
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return inBuffer
    }
    if let error { throw error }
    return Array(UnsafeBufferPointer(start: outBuffer.floatChannelData![0], count: Int(outBuffer.frameLength)))
}

/// Decodes any supported file to mono 48 kHz float.
func decodeMono48k(_ url: URL) throws -> [Float] {
    guard let file = try? AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false) else {
        return try decodeWithFFmpeg(url)
    }
    let format = file.processingFormat
    guard
        file.length > 0,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
    else { return [] }
    try file.read(into: buffer)
    let count = Int(buffer.frameLength)
    let channels = Int(format.channelCount)
    var mono = [Float](repeating: 0, count: count)
    for c in 0..<channels {
        let p = buffer.floatChannelData![c]
        for i in 0..<count { mono[i] += p[i] }
    }
    if channels > 1 {
        let scale = 1 / Float(channels)
        for i in 0..<count { mono[i] *= scale }
    }
    return format.sampleRate == targetRate ? mono : try resample(mono, from: format.sampleRate)
}

// MARK: - Processing

func peak(_ x: [Float]) -> Float {
    x.reduce(0) { max($0, abs($1)) }
}

/// Light trim: keep 1 ms before the attack and a short tail; fade both edges.
func trimSilence(_ x: [Float]) -> [Float] {
    let p = peak(x)
    guard p > 0, x.count > 64 else { return x }
    let startThreshold = p * 0.02 // -34 dB below the clip's peak
    let endThreshold = p * 0.003 // -50 dB
    let first = x.firstIndex { abs($0) >= startThreshold } ?? 0
    let last = x.lastIndex { abs($0) >= endThreshold } ?? (x.count - 1)
    let preRoll = Int(0.001 * targetRate)
    let tail = Int(0.005 * targetRate)
    let start = max(0, first - preRoll)
    let end = min(x.count, last + 1 + tail)
    guard end - start > 16 else { return x }
    var y = Array(x[start..<end])
    let fadeIn = first - start
    if fadeIn > 0 {
        for i in 0..<fadeIn { y[i] *= Float(i) / Float(fadeIn) }
    }
    let fadeOut = min(tail, y.count / 4)
    if fadeOut > 0 {
        for i in 0..<fadeOut { y[y.count - 1 - i] *= Float(i) / Float(fadeOut) }
    }
    return y
}

/// Quieter, shorter copy of the down sound, with a linear fade over its last 30 %.
func deriveUp(from down: [Float]) -> [Float] {
    let n = max(32, Int(Double(down.count) * derivedUpLength))
    var y = down.prefix(n).map { $0 * derivedUpGain }
    let fade = max(1, y.count * 3 / 10)
    for i in 0..<fade { y[y.count - 1 - i] *= Float(i) / Float(fade) }
    return y
}

func writeCAF(_ samples: [Float], to url: URL) throws {
    let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: targetRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]
    let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(samples.count)) else {
        throw ConvertError("Cannot allocate buffer for \(url.lastPathComponent)")
    }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    buffer.floatChannelData![0].update(from: samples, count: samples.count)
    try file.write(from: buffer)
}

// MARK: - Pack readers

struct Clip {
    var down: [Float]
    var up: [Float]?
}

func readPerKeyWAV(_ dir: URL, keyMap: [Int: UInt16]) throws -> [UInt16: Clip] {
    let regex = try NSRegularExpression(pattern: #"^(\d+)-(down|up)\.wav$"#, options: .caseInsensitive)
    var downs: [Int: URL] = [:]
    var ups: [Int: URL] = [:]
    for name in try fm.contentsOfDirectory(atPath: dir.path) {
        let range = NSRange(name.startIndex..., in: name)
        guard
            let match = regex.firstMatch(in: name, range: range),
            let idRange = Range(match.range(at: 1), in: name),
            let kindRange = Range(match.range(at: 2), in: name),
            let id = Int(name[idRange])
        else { continue }
        let url = dir.appendingPathComponent(name)
        if name[kindRange].lowercased() == "down" { downs[id] = url } else { ups[id] = url }
    }
    var clips: [UInt16: Clip] = [:]
    for id in downs.keys.sorted() {
        guard let code = keyMap[id] else {
            log("  skip unknown Mechvibes id \(id)")
            continue
        }
        guard clips[code] == nil else { continue }
        let down = trimSilence(try decodeMono48k(downs[id]!))
        let up = try ups[id].map { trimSilence(try decodeMono48k($0)) }
        clips[code] = Clip(down: down, up: up)
    }
    return clips
}

struct MechvibesConfig: Decodable {
    let name: String?
    let key_define_type: String?
    let sound: String?
    let defines: [String: [Double]?]
}

func readMechvibesSingle(_ dir: URL, keyMap: [Int: UInt16]) throws -> [UInt16: Clip] {
    let config = try JSONDecoder().decode(MechvibesConfig.self, from: Data(contentsOf: dir.appendingPathComponent("config.json")))
    guard (config.key_define_type ?? "single") == "single" else {
        throw ConvertError("Only Mechvibes 'single' packs are supported (\(dir.lastPathComponent))")
    }
    let soundName = config.sound ?? "sound.ogg"
    let audio = try decodeMono48k(dir.appendingPathComponent(soundName))
    guard !audio.isEmpty else { throw ConvertError("\(soundName) is empty") }

    var clips: [UInt16: Clip] = [:]
    let defines = config.defines.compactMap { key, value -> (Int, [Double])? in
        guard let id = Int(key), let value, value.count >= 2 else { return nil }
        return (id, value)
    }
    for (id, define) in defines.sorted(by: { $0.0 < $1.0 }) {
        guard let code = keyMap[id] else {
            log("  skip unknown Mechvibes id \(id)")
            continue
        }
        guard clips[code] == nil else { continue }
        let start = max(0, Int(define[0] / 1000 * targetRate))
        let end = min(audio.count, start + Int(define[1] / 1000 * targetRate))
        guard end - start > 32 else { continue }
        clips[code] = Clip(down: trimSilence(Array(audio[start..<end])), up: nil)
    }
    return clips
}

// MARK: - Theme writer

struct KeySamples: Encodable {
    let down: String
    let up: String?
}

struct Manifest: Encodable {
    let formatVersion = 1
    let name: String
    let sampleRate = targetRate
    let channels = 1
    let source: String
    let keys: [String: KeySamples]
    let fallbacks: [String: UInt16]
}

func convert(pack dir: URL, keyMap: [Int: UInt16]) throws {
    let name = dir.lastPathComponent
    let isMechvibes = fm.fileExists(atPath: dir.appendingPathComponent("config.json").path)
    log("• \(name) (\(isMechvibes ? "mechvibes-single" : "per-key-wav"))")
    var clips = isMechvibes ? try readMechvibesSingle(dir, keyMap: keyMap) : try readPerKeyWAV(dir, keyMap: keyMap)
    guard !clips.isEmpty else { throw ConvertError("\(name): no usable samples") }

    var derived = 0
    for (code, clip) in clips where clip.up == nil || clip.up!.isEmpty {
        clips[code]!.up = deriveUp(from: clip.down)
        derived += 1
    }

    let themePeak = clips.values.reduce(Float(0)) { max($0, peak($1.down), peak($1.up ?? [])) }
    let gain = themePeak > 0 ? peakTarget / themePeak : 1

    let outDir = themesDir.appendingPathComponent(name, isDirectory: true)
    if fm.fileExists(atPath: outDir.path) { try fm.removeItem(at: outDir) }
    try fm.createDirectory(at: outDir, withIntermediateDirectories: true)

    var keys: [String: KeySamples] = [:]
    for (code, clip) in clips {
        let downName = "\(code)-down.caf"
        try writeCAF(clip.down.map { $0 * gain }, to: outDir.appendingPathComponent(downName))
        var upName: String?
        if let up = clip.up, !up.isEmpty {
            upName = "\(code)-up.caf"
            try writeCAF(up.map { $0 * gain }, to: outDir.appendingPathComponent(upName!))
        }
        keys[String(code)] = KeySamples(down: downName, up: upName)
    }

    var fallbacks: [String: UInt16] = [:]
    for (groupName, preferred) in fallbackPreferences {
        if let code = preferred.first(where: { clips[$0] != nil })
            ?? clips.keys.sorted().first(where: { group(for: $0) == groupName }) {
            fallbacks[groupName] = code
        }
    }

    let manifest = Manifest(
        name: name,
        source: isMechvibes ? "mechvibes-single" : "per-key-wav",
        keys: keys,
        fallbacks: fallbacks
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: outDir.appendingPathComponent("theme.json"))
    log("  \(clips.count) keys, \(derived) derived ups, gain \(String(format: "%+.1f", 20 * log10(gain))) dB")
}

// MARK: - Main

do {
    guard fm.fileExists(atPath: soundsDir.path) else {
        throw ConvertError("Run from the repo root (no Sounds/ in \(root.path))")
    }
    let keyMap = try loadKeyMap()
    try fm.createDirectory(at: themesDir, withIntermediateDirectories: true)
    let packs = try fm.contentsOfDirectory(at: soundsDir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)
        .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    var failures = 0
    for pack in packs {
        do {
            try convert(pack: pack, keyMap: keyMap)
        } catch {
            failures += 1
            log("  ✗ \(error)")
        }
    }
    log("Converted \(packs.count - failures)/\(packs.count) packs into \(themesDir.path)")
    exit(failures == 0 ? 0 : 1)
} catch {
    log("error: \(error)")
    exit(1)
}
