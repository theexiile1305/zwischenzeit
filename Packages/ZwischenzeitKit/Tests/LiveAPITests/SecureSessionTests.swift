import Foundation
@testable import LiveAPI
import Testing

@Suite struct SecureSessionTests {
    @Test func storesNothingOnDisk() {
        let config = SecureSession.configuration()
        #expect(config.urlCache == nil)
        #expect(config.requestCachePolicy == .reloadIgnoringLocalCacheData)
        #expect(config.httpCookieStorage == nil)
        #expect(!config.httpShouldSetCookies)
        #expect(config.urlCredentialStorage == nil)
        #expect(config.tlsMinimumSupportedProtocolVersion == .TLSv12)
    }

    @Test func followsRedirectsOnlyToHttpsOnTheSameHost() {
        let base = URL(string: "https://www.ttools.app/ttools/rest/Termine/")
        #expect(RedirectGuard.allows(from: base, to: URL(string: "https://www.ttools.app/ttools/rest/Termine")))
        #expect(RedirectGuard.allows(from: base, to: URL(string: "https://WWW.ttools.app/other")))
        #expect(!RedirectGuard.allows(from: base, to: URL(string: "http://www.ttools.app/ttools/")))
        #expect(!RedirectGuard.allows(from: base, to: URL(string: "https://evil.example/ttools/")))
        #expect(!RedirectGuard.allows(from: base, to: URL(string: "https://www.ttools.app.evil.example/")))
        #expect(!RedirectGuard.allows(from: nil, to: base))
    }
}
