import Foundation

/// The URLSession for the live backend. Responses carry patient data, so nothing is cached
/// or stored: no URLCache (the shared session writes GET responses to Library/Caches),
/// no cookies, no credential storage. TLS 1.2 is the floor (ATS enforces it too).
public enum SecureSession {
    public static func configuration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.urlCredentialStorage = nil
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        return config
    }

    public static func make() -> URLSession {
        URLSession(configuration: configuration(), delegate: RedirectGuard(), delegateQueue: nil)
    }
}

/// Follows a redirect only to https on the same host, so the Bearer token and patient data
/// never leave the backend.
final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    static func allows(from original: URL?, to target: URL?) -> Bool {
        guard let original, let target, target.scheme?.lowercased() == "https",
              let host = original.host?.lowercased(), target.host?.lowercased() == host else { return false }
        return true
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        guard Self.allows(from: task.originalRequest?.url, to: request.url) else {
            liveLog.error("blocked redirect to another host or scheme")
            return nil
        }
        return request
    }
}
