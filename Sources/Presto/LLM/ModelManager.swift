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

public enum LocalModel: String, CaseIterable, Identifiable, Sendable {
    case qwen
    case hyMT
    case translateGemma

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .qwen:
            return "Qwen 2.5 1.5B"
        case .hyMT:
            return "HY-MT1.5 1.8B"
        case .translateGemma:
            return "TranslateGemma 4B"
        }
    }

    public var fileName: String {
        switch self {
        case .qwen:
            return "qwen2.5-1.5b-instruct-q4_k_m.gguf"
        case .hyMT:
            return "HY-MT1.5-1.8B-Q4_K_M.gguf"
        case .translateGemma:
            return "translategemma-4b-it-Q4_K_M.gguf"
        }
    }

    public var sizeLabel: String {
        switch self {
        case .qwen:
            return "~986 MB"
        case .hyMT:
            return "~1.1 GB"
        case .translateGemma:
            return "~2.5 GB"
        }
    }

    public var summary: String {
        switch self {
        case .qwen:
            return "General purpose · smallest download"
        case .hyMT:
            return "Translation-tuned · best quality per megabyte"
        case .translateGemma:
            return "Translation-tuned · widest language coverage"
        }
    }

    public var downloadURL: URL {
        switch self {
        case .qwen:
            return URL(string: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf?download=true")!
        case .hyMT:
            return URL(string: "https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf?download=true")!
        case .translateGemma:
            return URL(string: "https://huggingface.co/42ailab/TranslateGemma-4B-GGUF/resolve/main/translategemma-4b-it-Q4_K_M.gguf?download=true")!
        }
    }

    /// Gemma models ship a chat template that only accepts structured source/target blocks,
    /// so they get plain Gemma turns instead of `llama_chat_apply_template`.
    public var usesGemmaTurns: Bool {
        self == .translateGemma
    }
}

@MainActor
@Observable
public final class ModelManager {
    public static let shared = ModelManager()

    public private(set) var isDownloading: Bool = false
    public private(set) var downloadingModel: LocalModel?
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

    public func modelFileURL(for model: LocalModel) -> URL {
        modelsDirectoryURL.appendingPathComponent(model.fileName)
    }

    public func bundledModelURL(for model: LocalModel) -> URL? {
        guard let resourceURL = Bundle.main.resourceURL else { return nil }
        let modelsDir = resourceURL.appendingPathComponent("Models", isDirectory: true)
        let preferred = modelsDir.appendingPathComponent(model.fileName)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }
        // Offer a single bundled GGUF under another name (e.g. --bundle-model custom.gguf)
        let knownNames = Set(LocalModel.allCases.map(\.fileName))
        let contents = (try? FileManager.default.contentsOfDirectory(at: modelsDir, includingPropertiesForKeys: nil)) ?? []
        let extraGGUFs = contents.filter {
            $0.pathExtension.lowercased() == "gguf" && !knownNames.contains($0.lastPathComponent)
        }
        return extraGGUFs.count == 1 ? extraGGUFs[0] : nil
    }

    public func isDownloaded(_ model: LocalModel) -> Bool {
        _ = modelRevision
        return FileManager.default.fileExists(atPath: modelFileURL(for: model).path)
    }

    public func resolvedURL(for model: LocalModel) -> URL? {
        _ = modelRevision
        if let bundled = bundledModelURL(for: model) {
            return bundled
        }
        if isDownloaded(model) {
            return modelFileURL(for: model)
        }
        return nil
    }

    /// The explicitly chosen custom `.gguf`, only when it exists on disk.
    public var customModelURL: URL? {
        _ = modelRevision
        guard let path = AppPreferences.shared.customModelPath,
              !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    /// True when the given engine can translate right now without a download.
    /// Apple Intelligence is not covered: callers check its availability separately.
    public func isReady(_ engine: EnginePreference) -> Bool {
        if engine == .custom {
            return customModelURL != nil
        }
        guard let model = engine.localModel else { return false }
        return resolvedURL(for: model) != nil
    }

    /// GGUF files start with the "GGUF" magic bytes.
    public func isGGUFFile(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "gguf",
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: 4)) == Data("GGUF".utf8)
    }

    public func statusSummary(for model: LocalModel) -> String {
        _ = modelRevision
        if let bundled = bundledModelURL(for: model) {
            return "Bundled in app (\(bundled.lastPathComponent))"
        }
        if isDownloaded(model) {
            return "Ready (\(model.fileName))"
        }
        return "Not downloaded (\(model.sizeLabel))"
    }

    public func refreshState() {
        modelRevision += 1
    }

    @discardableResult
    public func download(_ model: LocalModel) async throws -> URL {
        if let existing = resolvedURL(for: model) {
            return existing
        }

        if isDownloading {
            throw ModelManagerError.downloadFailed("A download is already in progress.")
        }

        try FileManager.default.createDirectory(at: modelsDirectoryURL, withIntermediateDirectories: true)

        isDownloading = true
        downloadingModel = model
        downloadProgress = 0
        downloadError = nil

        let destination = modelFileURL(for: model)

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
            let task = session.downloadTask(with: model.downloadURL)
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
        downloadingModel = nil
        downloadProgress = 0
        if let continuation = activeDownloadContinuation {
            activeDownloadContinuation = nil
            continuation.resume(throwing: ModelManagerError.downloadCancelled)
        }
    }

    public func deleteModel(_ model: LocalModel) throws {
        let url = modelFileURL(for: model)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        refreshState()
    }

    private func finishDownload(result: Result<URL, Error>, destination: URL) {
        defer {
            isDownloading = false
            downloadingModel = nil
            activeDownloadTask = nil
            activeDownloadDelegate = nil
            refreshState()
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
