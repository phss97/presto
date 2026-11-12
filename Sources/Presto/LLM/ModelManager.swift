import Foundation
import Observation

public enum ModelManagerError: LocalizedError, Sendable {
    case downloadFailed(String)
    case downloadCancelled

    public var errorDescription: String? {
        switch self {
        case .downloadFailed(let message):
            return "Model download failed: \(message)"
        case .downloadCancelled:
            return "Model download was cancelled."
        }
    }
}

@MainActor
@Observable
public final class ModelManager {
    public static let shared = ModelManager()

    public static let defaultModelFileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    public static let defaultModelDisplayName = "Qwen 2.5 1.5B Instruct (Q4_K_M · ~986 MB)"
    public static let defaultModelDownloadURL = URL(
        string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true"
    )!

    public private(set) var isDownloading: Bool = false
    public private(set) var downloadProgress: Double = 0
    public private(set) var downloadError: String?
    public private(set) var modelRevision: Int = 0

    private var activeDownloadDelegate: DownloadSessionDelegate?
    private var activeDownloadTask: URLSessionDownloadTask?
    private var activeDownloadContinuation: CheckedContinuation<URL, Error>?

    private init() {}

    public var modelsDirectoryURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Presto/Models", isDirectory: true)
    }

    public var downloadedDefaultModelURL: URL {
        modelsDirectoryURL.appendingPathComponent(Self.defaultModelFileName)
    }

    public var bundledModelURL: URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let modelsDir = resourceURL.appendingPathComponent("Models", isDirectory: true)
        let preferred = modelsDir.appendingPathComponent(Self.defaultModelFileName)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil),
           let firstGGUF = contents.first(where: { $0.pathExtension.lowercased() == "gguf" }) {
            return firstGGUF
        }
        return nil
    }

    public var resolvedModelURL: URL? {
        _ = modelRevision
        if let custom = AppPreferences.shared.customModelPath,
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return URL(fileURLWithPath: custom)
        }
        if let bundled = bundledModelURL {
            return bundled
        }
        let downloaded = downloadedDefaultModelURL
        if FileManager.default.fileExists(atPath: downloaded.path) {
            return downloaded
        }
        return nil
    }

    public var modelStatusSummary: String {
        _ = modelRevision
        if let custom = AppPreferences.shared.customModelPath,
           !custom.isEmpty,
           FileManager.default.fileExists(atPath: custom) {
            return "Custom: \((custom as NSString).lastPathComponent)"
        }
        if let bundled = bundledModelURL {
            return "Bundled in app (\(bundled.lastPathComponent))"
        }
        if FileManager.default.fileExists(atPath: downloadedDefaultModelURL.path) {
            return "Ready (\(Self.defaultModelFileName))"
        }
        return "Not downloaded (~986 MB)"
    }

    public func refreshState() {
        modelRevision += 1
    }

    public func ensureModelAvailable() async throws -> URL {
        if let existing = resolvedModelURL {
            return existing
        }
        return try await downloadDefaultModel()
    }

    @discardableResult
    public func downloadDefaultModel() async throws -> URL {
        if let existing = resolvedModelURL {
            return existing
        }

        if isDownloading {
            throw ModelManagerError.downloadFailed("A download is already in progress.")
        }

        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

        isDownloading = true
        downloadProgress = 0
        downloadError = nil

        let destination = downloadedDefaultModelURL

        return try await withCheckedThrowingContinuation { continuation in
            self.activeDownloadContinuation = continuation

            let delegate = DownloadSessionDelegate(
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.downloadProgress = fraction
                    }
                },
                onComplete: { [weak self] result in
                    Task { @MainActor in
                        self?.finishDownload(result: result, destination: destination)
                    }
                }
            )
            self.activeDownloadDelegate = delegate

            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let task = session.downloadTask(with: Self.defaultModelDownloadURL)
            self.activeDownloadTask = task
            task.resume()
        }
    }

    public func cancelDownload() {
        guard isDownloading else { return }
        activeDownloadTask?.cancel()
        activeDownloadTask = nil
        activeDownloadDelegate = nil
        isDownloading = false
        downloadProgress = 0
        if let continuation = activeDownloadContinuation {
            activeDownloadContinuation = nil
            continuation.resume(throwing: ModelManagerError.downloadCancelled)
        }
    }

    public func deleteDownloadedModel() throws {
        let url = downloadedDefaultModelURL
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refreshState()
    }

    private func finishDownload(result: Result<URL, Error>, destination: URL) {
        defer {
            isDownloading = false
            activeDownloadTask = nil
            activeDownloadDelegate = nil
        }

        guard let continuation = activeDownloadContinuation else { return }
        activeDownloadContinuation = nil

        switch result {
        case .success(let tempFileURL):
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempFileURL, to: destination)
                downloadProgress = 1.0
                refreshState()
                continuation.resume(returning: destination)
            } catch {
                try? FileManager.default.removeItem(at: tempFileURL)
                downloadError = error.localizedDescription
                continuation.resume(throwing: ModelManagerError.downloadFailed(error.localizedDescription))
            }
        case .failure(let error):
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                continuation.resume(throwing: ModelManagerError.downloadCancelled)
            } else {
                downloadError = error.localizedDescription
                continuation.resume(throwing: ModelManagerError.downloadFailed(error.localizedDescription))
            }
        }
    }
}

private final class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    private let onProgress: @Sendable (Double) -> Void
    private let onComplete: @Sendable (Result<URL, Error>) -> Void

    init(
        onProgress: @escaping @Sendable (Double) -> Void,
        onComplete: @escaping @Sendable (Result<URL, Error>) -> Void
    ) {
        self.onProgress = onProgress
        self.onComplete = onComplete
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0.0), 1.0)
        onProgress(fraction)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        if let httpResponse = downloadTask.response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            onComplete(.failure(ModelManagerError.downloadFailed("HTTP \(httpResponse.statusCode)")))
            session.finishTasksAndInvalidate()
            return
        }

        // Copy to a stable temporary file before URLSession deletes `location` upon return
        let stableTemp = FileManager.default.temporaryDirectory
            .appendingPathComponent("presto-model-\(UUID().uuidString).gguf")
        do {
            try FileManager.default.moveItem(at: location, to: stableTemp)
            onComplete(.success(stableTemp))
        } catch {
            onComplete(.failure(error))
        }
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            onComplete(.failure(error))
            session.finishTasksAndInvalidate()
        }
    }
}
