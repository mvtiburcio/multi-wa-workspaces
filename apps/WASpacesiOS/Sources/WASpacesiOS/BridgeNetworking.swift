import Foundation

enum BridgeNetworking {
  static func makeSession(allowInsecureTLS: Bool) -> URLSession {
    guard allowInsecureTLS else {
      return .shared
    }
    let configuration = URLSessionConfiguration.default
    return URLSession(
      configuration: configuration,
      delegate: InsecureTLSDelegate(),
      delegateQueue: nil
    )
  }
}

private final class InsecureTLSDelegate: NSObject, URLSessionDelegate {
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
          let trust = challenge.protectionSpace.serverTrust else {
      completionHandler(.performDefaultHandling, nil)
      return
    }
    completionHandler(.useCredential, URLCredential(trust: trust))
  }
}
