import Foundation
import SwiftSignalKit

public func requestsDownload(url: URL) -> Signal<(Data, URLResponse?), Error?> {
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)

        let downloadTask = URLSession.shared.downloadTask(with: url, completionHandler: { location, response, error in
            let _ = completed.swap(true)
            if let location = location, let data = try? Data(contentsOf: location) {
                subscriber.putNext((data, response))
                subscriber.putCompletion()
            } else {
                subscriber.putError(error)
            }
        })
        downloadTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                downloadTask.cancel()
            }
        }
    }
}

public func requestsGet(url: URL) -> Signal<(Data, URLResponse?), Error?> {
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)

        let urlTask = URLSession.shared.dataTask(with: url, completionHandler: { data, response, error in
            let _ = completed.swap(true)
            if let strongData = data {
                subscriber.putNext((strongData, response))
                subscriber.putCompletion()
            } else {
                subscriber.putError(error)
            }
        })
        urlTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                urlTask.cancel()
            }
        }
    }
}

public func requestsCustom(request: URLRequest) -> Signal<(Data, URLResponse?), Error?> {
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)
        let urlTask = URLSession.shared.dataTask(with: request, completionHandler: { data, response, error in
            _ = completed.swap(true)
            if let strongData = data {
                subscriber.putNext((strongData, response))
                subscriber.putCompletion()
            } else {
                subscriber.putError(error)
            }
        })
        urlTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                urlTask.cancel()
            }
        }
    }
}

/// Same as requestsCustom but with SSL certificate pinning. Use for supporters API.
/// - Parameters:
///   - request: The URL request
///   - host: Expected host (e.g. "luxgram.site")
///   - pinnedHashes: Base64 SHA256 hashes of server cert(s). Empty = no pinning (fallback to default).
public func requestsCustomWithPinning(
    request: URLRequest,
    host: String,
    pinnedHashes: [String]
) -> Signal<(Data, URLResponse?), Error?> {
    guard !pinnedHashes.isEmpty else {
        return requestsCustom(request: request)
    }
    return Signal { subscriber in
        let completed = Atomic<Bool>(value: false)
        let delegate = SSLPinningDelegate(host: host, pinnedHashes: pinnedHashes)
        let config = URLSessionConfiguration.default
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        let urlTask = session.dataTask(with: request, completionHandler: { data, response, error in
            _ = completed.swap(true)
            session.finishTasksAndInvalidate()
            if let strongData = data {
                subscriber.putNext((strongData, response))
                subscriber.putCompletion()
            } else {
                subscriber.putError(error)
            }
        })
        urlTask.resume()

        return ActionDisposable {
            if !completed.with({ $0 }) {
                urlTask.cancel()
            }
        }
    }
}
