import AVFoundation

/// Captures the default microphone and resamples to 16 kHz mono Float32, the format
/// whisper.cpp expects.
final class AudioRecorder {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Double(WhisperEngine.sampleRate),
        channels: 1,
        interleaved: false
    )!

    /// RMS level of the latest buffer, 0…1, delivered on the main queue.
    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    func start() throws {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw NSError(domain: "VaultoNote", code: 1, userInfo: [
                NSLocalizedDescriptionKey: L10n.t("error.mic_unavailable"),
            ])
        }
        converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRecording = true
    }

    /// Stops capture and returns everything recorded since `start()`.
    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = output.floatChannelData?[0] else { return }
        let chunk = UnsafeBufferPointer(start: channel, count: Int(output.frameLength))

        lock.lock()
        samples.append(contentsOf: chunk)
        lock.unlock()

        if let onLevel, !chunk.isEmpty {
            let rms = sqrt(chunk.reduce(0) { $0 + $1 * $1 } / Float(chunk.count))
            let level = min(1, rms * 12)
            DispatchQueue.main.async { onLevel(level) }
        }
    }
}

enum AudioFileLoader {
    /// Reads any audio file AVFoundation understands as 16 kHz mono Float32.
    static func load(url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let inputFormat = file.processingFormat
        guard let input = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            return []
        }
        try file.read(into: input)
        guard let converter = AVAudioConverter(from: inputFormat, to: AudioRecorder.targetFormat) else { return [] }
        let capacity = AVAudioFrameCount(Double(input.frameLength) * AudioRecorder.targetFormat.sampleRate / inputFormat.sampleRate) + 1024
        guard let output = AVAudioPCMBuffer(pcmFormat: AudioRecorder.targetFormat, frameCapacity: capacity) else { return [] }
        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .endOfStream
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        return Array(UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength)))
    }
}
