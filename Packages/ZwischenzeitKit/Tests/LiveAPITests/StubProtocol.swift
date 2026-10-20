import Foundation

/// Routes every request of a test URLSession to `handler`, and records them.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []
    static let lock = NSLock()

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: config)
    }

    static func reset(_ handler: @escaping @Sendable (URLRequest) -> (Int, Data)) {
        lock.withLock { requests = []; self.handler = handler }
    }

    static func paths() -> [String] { lock.withLock { requests.map { $0.url!.path } } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        var r = request
        if r.httpBody == nil, let stream = r.httpBodyStream {
            stream.open()
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            stream.close()
            r.httpBody = data
        }
        Self.lock.withLock { Self.requests.append(r) }
        let (status, data) = Self.handler?(r) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: r.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
}

/// An unsigned JWT with the given claims; the client never checks signatures.
func jwt(_ claims: [String: Any]) -> String {
    func b64(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = b64(try! JSONSerialization.data(withJSONObject: ["alg": "none"]))
    return "\(header).\(b64(try! JSONSerialization.data(withJSONObject: claims))).sig"
}

func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }
