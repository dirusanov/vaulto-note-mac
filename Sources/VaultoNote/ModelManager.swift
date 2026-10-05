import Foundation

struct WhisperModel: Identifiable, Equatable {
    let id: String
    let name: String
    let sizeGB: Double
    let filename: String
    /// 1…5, relative within this list; shown as dots on the model card.
    let speed: Int
    let accuracy: Int
    let isRecommended: Bool

    var summary: String { L10n.t("model.summary.\(id)") }
    var sizeLabel: String { L10n.size(gigabytes: sizeGB) }
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")! }
    var fileURL: URL { AppPaths.models.appendingPathComponent(filename) }
    var isDownloaded: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    static let all: [WhisperModel] = [
        .init(id: "turbo", name: "Large v3 Turbo", sizeGB: 1.6, filename: "ggml-large-v3-turbo.bin",
              speed: 4, accuracy: 4, isRecommended: true),
        .init(id: "turbo-q5", name: "Turbo Compact", sizeGB: 0.574, filename: "ggml-large-v3-turbo-q5_0.bin",
              speed: 5, accuracy: 3, isRecommended: false),
        .init(id: "large", name: "Large v3", sizeGB: 3.1, filename: "ggml-large-v3.bin",
              speed: 2, accuracy: 5, isRecommended: false),
    ]

    static let defaultModel = all[0]

    static func find(_ id: String) -> WhisperModel {
        all.first { $0.id == id } ?? defaultModel
    }
}

/// Downloads ggml weights into Application Support. One download at a time.
final class ModelManager: NSObject, URLSessionDownloadDelegate {
    private(set) var downloading: WhisperModel?
    var onProgress: ((Double) -> Void)?
    private var completion: ((Result<URL, Error>) -> Void)?
    private var task: URLSessionDownloadTask?
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)

    func download(_ model: WhisperModel, completion: @escaping (Result<URL, Error>) -> Void) {
        guard downloading == nil else { return }
        downloading = model
        self.completion = completion
        task = session.downloadTask(with: model.url)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        task = nil
        downloading = nil
        completion = nil
    }

    func delete(_ model: WhisperModel) {
        try? FileManager.default.removeItem(at: model.fileURL)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData _: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress?(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let model = downloading else { return }
        do {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw NSError(domain: "VaultoNote", code: http.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: L10n.t("error.http", http.statusCode),
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
        task = nil
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
                NSLocalizedDescriptionKey: L10n.t("error.not_a_model"),
            ])
        }
    }
}
