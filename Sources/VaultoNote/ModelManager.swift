import Foundation

struct WhisperModel {
    let id: String
    let title: String
    let sizeLabel: String
    let filename: String

    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")! }
    var fileURL: URL { AppPaths.models.appendingPathComponent(filename) }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static let all: [WhisperModel] = [
        .init(id: "turbo", title: "Large v3 Turbo", sizeLabel: "1,6 ГБ", filename: "ggml-large-v3-turbo.bin"),
        .init(id: "turbo-q5", title: "Large v3 Turbo (сжатая)", sizeLabel: "574 МБ", filename: "ggml-large-v3-turbo-q5_0.bin"),
        .init(id: "large", title: "Large v3", sizeLabel: "3,1 ГБ", filename: "ggml-large-v3.bin"),
    ]

    static let defaultModel = all[0]

    static func find(_ id: String) -> WhisperModel {
        all.first { $0.id == id } ?? defaultModel
    }
}

/// Downloads ggml weights into Application Support. One download at a time.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
    private(set) var downloading: WhisperModel?
    private(set) var progress: Double = 0
    var onProgress: ((Double) -> Void)?
    private var completion: ((Result<URL, Error>) -> Void)?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func download(_ model: WhisperModel, completion: @escaping (Result<URL, Error>) -> Void) {
        guard downloading == nil else { return }
        downloading = model
        progress = 0
        self.completion = completion
        session.downloadTask(with: model.url).resume()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress?(progress)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = downloading else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "VaultoNote", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "Сервер моделей ответил HTTP \(http.statusCode)",
                ])
            }
            try Self.validate(location)
            try? FileManager.default.removeItem(at: model.fileURL)
            try FileManager.default.moveItem(at: location, to: model.fileURL)
            finish(.success(model.fileURL))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard downloading != nil else { return }
        downloading = nil
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    /// ggml weights start with the magic "lmgg" (little-endian "ggml"); an HTML error
    /// page saved as a model would crash the native loader.
    private static func validate(_ url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let magic = String(decoding: handle.readData(ofLength: 4), as: UTF8.self)
        guard magic == "lmgg" || magic == "ggml" else {
            throw NSError(domain: "VaultoNote", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "Скачанный файл не является моделью Whisper",
            ])
        }
    }
}
