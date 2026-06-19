import AVFoundation
import Combine
import Foundation
import UserNotifications

@MainActor
final class NotificationSoundSettings: ObservableObject {
    static let shared = NotificationSoundSettings()

    @Published private(set) var revision = UUID()
    private let defaults = UserDefaults.standard

    private init() {
        ensureBuiltInSounds()
    }

    func displayName(for outcome: ReplyOutcome) -> String {
        guard let name = defaults.string(forKey: key(for: outcome)) else {
            return "内置专属提示音"
        }
        return name
    }

    func notificationSound(for outcome: ReplyOutcome) -> UNNotificationSound {
        let name = defaults.string(forKey: key(for: outcome)) ?? builtInName(for: outcome)
        return UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
    }

    func importSound(from sourceURL: URL, for outcome: ReplyOutcome) throws {
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { sourceURL.stopAccessingSecurityScopedResource() }
        }

        let duration = try AVAudioPlayer(contentsOf: sourceURL).duration
        guard duration.isFinite, duration > 0, duration <= 30 else {
            throw SoundError.invalidDuration
        }

        let ext = sourceURL.pathExtension.lowercased()
        guard ["caf", "wav", "aif", "aiff"].contains(ext) else {
            throw SoundError.unsupportedFormat
        }

        let directory = try soundsDirectory()
        removeImportedSound(for: outcome)
        let fileName = "tavern_\(outcome.rawValue)_custom.\(ext)"
        let destination = directory.appendingPathComponent(fileName)
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        defaults.set(fileName, forKey: key(for: outcome))
        revision = UUID()
    }

    func restoreBuiltInSound(for outcome: ReplyOutcome) {
        removeImportedSound(for: outcome)
        defaults.removeObject(forKey: key(for: outcome))
        revision = UUID()
    }

    private func removeImportedSound(for outcome: ReplyOutcome) {
        guard let name = defaults.string(forKey: key(for: outcome)),
              name.contains("_custom."),
              let directory = try? soundsDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private func ensureBuiltInSounds() {
        guard let directory = try? soundsDirectory() else { return }
        let tones: [(ReplyOutcome, [Double])] = [
            (.complete, [659.25, 783.99, 987.77]),
            (.truncated, [659.25, 523.25]),
            (.empty, [392.00, 329.63, 261.63])
        ]
        for (outcome, frequencies) in tones {
            let url = directory.appendingPathComponent(builtInName(for: outcome))
            if !FileManager.default.fileExists(atPath: url.path) {
                try? Self.writeToneWav(frequencies: frequencies, to: url)
            }
        }
    }

    private func soundsDirectory() throws -> URL {
        let library = try FileManager.default.url(
            for: .libraryDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = library.appendingPathComponent("Sounds", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func key(for outcome: ReplyOutcome) -> String {
        "notificationSound.\(outcome.rawValue)"
    }

    private func builtInName(for outcome: ReplyOutcome) -> String {
        "tavern_\(outcome.rawValue)_built_in.wav"
    }

    private static func writeToneWav(frequencies: [Double], to url: URL) throws {
        let sampleRate = 22_050
        let toneDuration = 0.16
        let gapDuration = 0.045
        var samples = [Int16]()

        for (index, frequency) in frequencies.enumerated() {
            let count = Int(Double(sampleRate) * toneDuration)
            for sample in 0..<count {
                let progress = Double(sample) / Double(max(1, count - 1))
                let envelope = min(progress * 10, min((1 - progress) * 8, 1))
                let value = sin(2 * .pi * frequency * Double(sample) / Double(sampleRate))
                samples.append(Int16(value * envelope * 16_000))
            }
            if index < frequencies.count - 1 {
                samples.append(contentsOf: repeatElement(0, count: Int(Double(sampleRate) * gapDuration)))
            }
        }

        let dataSize = UInt32(samples.count * MemoryLayout<Int16>.size)
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(UInt32(sampleRate).littleEndianData)
        data.append(UInt32(sampleRate * 2).littleEndianData)
        data.append(UInt16(2).littleEndianData)
        data.append(UInt16(16).littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndianData)
        for sample in samples {
            data.append(sample.littleEndianData)
        }
        try data.write(to: url, options: .atomic)
    }

    enum SoundError: LocalizedError {
        case invalidDuration
        case unsupportedFormat

        var errorDescription: String? {
            switch self {
            case .invalidDuration: return "提示音必须大于 0 秒且不超过 30 秒。"
            case .unsupportedFormat: return "请选择 CAF、WAV、AIF 或 AIFF 音频。"
            }
        }
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
