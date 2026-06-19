import AVFoundation
import UIKit

@MainActor
final class BackgroundKeepAliveService {
    static let shared = BackgroundKeepAliveService()

    private var player: AVAudioPlayer?
    private var reasons = Set<String>()

    func start(reason: String) {
        reasons.insert(reason)
        configureSession()
        ensurePlayer()
        player?.play()
    }

    func stop(reason: String) {
        reasons.remove(reason)
        guard reasons.isEmpty else { return }
        player?.stop()
    }

    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
    }

    private func ensurePlayer() {
        guard player == nil else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tavern-silent-loop.wav")
        if !FileManager.default.fileExists(atPath: url.path) {
            Self.writeSilentWav(to: url)
        }
        guard let newPlayer = try? AVAudioPlayer(contentsOf: url) else { return }
        newPlayer.numberOfLoops = -1
        newPlayer.volume = 0.01
        newPlayer.prepareToPlay()
        player = newPlayer
    }

    private static func writeSilentWav(to url: URL) {
        let sampleRate: UInt32 = 8000
        let seconds: UInt32 = 1
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let dataSize = sampleRate * seconds * UInt32(channels) * UInt32(bitsPerSample / 8)
        var data = Data()
        data.append("RIFF".data(using: .ascii)!)
        data.append(UInt32(36 + dataSize).littleEndianData)
        data.append("WAVEfmt ".data(using: .ascii)!)
        data.append(UInt32(16).littleEndianData)
        data.append(UInt16(1).littleEndianData)
        data.append(channels.littleEndianData)
        data.append(sampleRate.littleEndianData)
        data.append((sampleRate * UInt32(channels) * UInt32(bitsPerSample / 8)).littleEndianData)
        data.append((channels * bitsPerSample / 8).littleEndianData)
        data.append(bitsPerSample.littleEndianData)
        data.append("data".data(using: .ascii)!)
        data.append(dataSize.littleEndianData)
        data.append(Data(repeating: 0, count: Int(dataSize)))
        try? data.write(to: url)
    }
}

private extension FixedWidthInteger {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<Self>.size)
    }
}
