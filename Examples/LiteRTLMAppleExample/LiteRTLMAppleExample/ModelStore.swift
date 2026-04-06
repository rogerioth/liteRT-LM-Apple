import Foundation

struct ModelDownloadProgress: Sendable {
    let completedBytes: Int64
    let totalBytes: Int64

    var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }

    var percentDescription: String {
        "\(Int((fractionCompleted * 100).rounded()))%"
    }

    var completedDescription: String {
        ByteCountFormatter.string(fromByteCount: completedBytes, countStyle: .file)
    }

    var totalDescription: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }
}

enum ModelStoreError: LocalizedError {
    case invalidHTTPResponse
    case downloadFailed(statusCode: Int)
    case downloadDidNotProduceFile
    case fileSizeMismatch(expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "The model download did not return a valid HTTP response."
        case .downloadFailed(let statusCode):
            return "The model download failed with HTTP status \(statusCode)."
        case .downloadDidNotProduceFile:
            return "The model download finished without producing a local file."
        case .fileSizeMismatch(let expected, let actual):
            return "Downloaded file size mismatch. Expected \(expected) bytes, received \(actual) bytes."
        }
    }
}

struct ModelStore {
    private let fileManager = FileManager.default

    var modelsDirectory: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("LiteRTLMAppleExample/Models", isDirectory: true)
    }

    var cacheDirectory: URL {
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("LiteRTLMAppleExample/Cache", isDirectory: true)
    }

    func localURL(for model: ExampleModelDescriptor) -> URL {
        modelsDirectory.appendingPathComponent(model.fileName, isDirectory: false)
    }

    func localURLIfPresent(for model: ExampleModelDescriptor) throws -> URL? {
        try prepareDirectories()
        let url = localURL(for: model)

        guard fileManager.fileExists(atPath: url.path) else {
            ConsoleLog.debug("Local model not found at \(url.path).", category: "ModelStore")
            return nil
        }

        let fileSize = try fileSizeOfItem(at: url)
        guard fileSize == model.sizeInBytes else {
            ConsoleLog.error(
                "Local model size mismatch at \(url.path). expected=\(model.sizeInBytes) actual=\(fileSize). Removing stale file.",
                category: "ModelStore"
            )
            try? fileManager.removeItem(at: url)
            return nil
        }

        ConsoleLog.info(
            "Reusing existing local model \(model.displayName) at \(url.path) (\(fileSize) bytes).",
            category: "ModelStore"
        )
        return url
    }

    func delete(_ model: ExampleModelDescriptor) throws {
        let url = localURL(for: model)
        guard fileManager.fileExists(atPath: url.path) else { return }
        ConsoleLog.info("Removing model file at \(url.path).", category: "ModelStore")
        try fileManager.removeItem(at: url)
    }

    func download(
        _ model: ExampleModelDescriptor,
        onProgress: @escaping @MainActor @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        try prepareDirectories()

        if let existingURL = try localURLIfPresent(for: model) {
            return existingURL
        }

        let destinationURL = localURL(for: model)
        let coordinator = DownloadCoordinator(
            destinationURL: destinationURL,
            expectedSize: model.sizeInBytes,
            progressHandler: onProgress
        )

        ConsoleLog.info(
            "Prepared download for \(model.displayName). remote=\(model.downloadURL.absoluteString) destination=\(destinationURL.path).",
            category: "ModelStore"
        )
        return try await coordinator.download(from: model.downloadURL)
    }

    private func prepareDirectories() throws {
        try prepareDirectory(modelsDirectory, excludeFromBackup: true)
        try prepareDirectory(cacheDirectory, excludeFromBackup: true)
    }

    private func prepareDirectory(_ url: URL, excludeFromBackup: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        ConsoleLog.debug(
            "Ensured directory exists at \(url.path) excludeFromBackup=\(excludeFromBackup).",
            category: "ModelStore"
        )

        guard excludeFromBackup else { return }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true

        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func fileSizeOfItem(at url: URL) throws -> Int64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }
}

private final class DownloadCoordinator: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedSize: Int64
    private let progressHandler: @MainActor @Sendable (ModelDownloadProgress) -> Void
    private let fileManager = FileManager.default

    private var continuation: CheckedContinuation<URL, Error>?
    private var movedFileURL: URL?
    private var completionError: Error?
    private var activeTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var lastLoggedPercent = -1

    init(
        destinationURL: URL,
        expectedSize: Int64,
        progressHandler: @escaping @MainActor @Sendable (ModelDownloadProgress) -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedSize = expectedSize
        self.progressHandler = progressHandler
    }

    func download(from remoteURL: URL) async throws -> URL {
        let request = URLRequest(url: remoteURL)
        ConsoleLog.info(
            "Opening URLSession download. remote=\(remoteURL.absoluteString) destination=\(destinationURL.path) expected_bytes=\(expectedSize).",
            category: "Download"
        )

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation

                let configuration = URLSessionConfiguration.default
                configuration.allowsConstrainedNetworkAccess = true
                configuration.allowsExpensiveNetworkAccess = true
                configuration.waitsForConnectivity = true
                configuration.requestCachePolicy = .reloadIgnoringLocalCacheData

                let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                let task = session.downloadTask(with: request)

                self.session = session
                self.activeTask = task
                ConsoleLog.debug("Resuming download task.", category: "Download")
                task.resume()
            }
        } onCancel: { [weak self] in
            ConsoleLog.error("Cancelling download task for \(remoteURL.absoluteString).", category: "Download")
            self?.activeTask?.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let totalBytes = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        let progress = ModelDownloadProgress(
            completedBytes: totalBytesWritten,
            totalBytes: totalBytes
        )
        let percent = Int((progress.fractionCompleted * 100).rounded())
        if percent != lastLoggedPercent && (percent == 100 || percent % 5 == 0) {
            lastLoggedPercent = percent
            ConsoleLog.info(
                "Download progress \(percent)% (\(progress.completedDescription) / \(progress.totalDescription)).",
                category: "Download"
            )
        }

        Task { @MainActor in
            progressHandler(progress)
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            guard let httpResponse = downloadTask.response as? HTTPURLResponse else {
                completionError = ModelStoreError.invalidHTTPResponse
                ConsoleLog.error("Download finished without a valid HTTP response.", category: "Download")
                return
            }

            guard (200 ... 299).contains(httpResponse.statusCode) else {
                completionError = ModelStoreError.downloadFailed(statusCode: httpResponse.statusCode)
                ConsoleLog.error(
                    "Download failed with HTTP status \(httpResponse.statusCode).",
                    category: "Download"
                )
                return
            }

            ConsoleLog.info(
                "Download finished to temporary file \(location.path) with HTTP \(httpResponse.statusCode).",
                category: "Download"
            )

            if fileManager.fileExists(atPath: destinationURL.path) {
                ConsoleLog.debug("Removing existing destination file at \(destinationURL.path).", category: "Download")
                try fileManager.removeItem(at: destinationURL)
            }

            try fileManager.moveItem(at: location, to: destinationURL)

            let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            if expectedSize > 0 && actualSize != expectedSize {
                try? fileManager.removeItem(at: destinationURL)
                completionError = ModelStoreError.fileSizeMismatch(
                    expected: expectedSize,
                    actual: actualSize
                )
                ConsoleLog.error(
                    "Downloaded file size mismatch at \(destinationURL.path). expected=\(expectedSize) actual=\(actualSize).",
                    category: "Download"
                )
                return
            }

            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(values)

            movedFileURL = destinationURL
            ConsoleLog.info(
                "Moved downloaded model into place at \(destinationURL.path) (\(actualSize) bytes).",
                category: "Download"
            )
        } catch {
            completionError = error
            ConsoleLog.error("Failed while finalizing download: \(error)", category: "Download")
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        defer {
            continuation = nil
            activeTask = nil
            movedFileURL = nil
            session.finishTasksAndInvalidate()
            self.session = nil
        }

        if let error {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                ConsoleLog.error("Download task cancelled by caller.", category: "Download")
                continuation?.resume(throwing: CancellationError())
            } else {
                ConsoleLog.error("Download task completed with error: \(error).", category: "Download")
                continuation?.resume(throwing: error)
            }
            return
        }

        if let completionError {
            ConsoleLog.error("Download coordinator finished with error: \(completionError).", category: "Download")
            continuation?.resume(throwing: completionError)
            return
        }

        guard let movedFileURL else {
            ConsoleLog.error("Download completed but no final file URL was produced.", category: "Download")
            continuation?.resume(throwing: ModelStoreError.downloadDidNotProduceFile)
            return
        }

        ConsoleLog.info("Download coordinator completed successfully.", category: "Download")
        continuation?.resume(returning: movedFileURL)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        ConsoleLog.info(
            "HTTP redirect \(response.statusCode) -> \(request.url?.absoluteString ?? "nil").",
            category: "Download"
        )
        completionHandler(request)
    }
}
