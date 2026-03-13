import Foundation
import Network
import Security

class SSLService {
    static let shared = SSLService()
    
    private init() {}
    
    func fetchSSLInfo(for host: String) async throws -> (expiryDate: Date?, ipAddress: String?) {
        let fetcher = SSLInfoFetcher()
        let expiryDate = try await fetcher.fetchExpiry(for: host)
        let ip = await resolveIP(for: host)
        return (expiryDate, ip)
    }
    
    /// Resolve IP address for a given host using DNS lookup
    func resolveIP(for host: String) async -> String? {
        let cleanHost = host
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .init(charactersIn: "/ "))
        
        return await withCheckedContinuation { continuation in
            var hints = addrinfo()
            hints.ai_family = AF_UNSPEC
            hints.ai_socktype = SOCK_STREAM
            
            var res: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(cleanHost, nil, &hints, &res)
            
            guard status == 0, let info = res else {
                continuation.resume(returning: nil)
                return
            }
            
            defer { freeaddrinfo(res) }
            
            var ipString: String?
            var ptr = info
            while true {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(ptr.pointee.ai_addr, ptr.pointee.ai_addrlen,
                               &hostname, socklen_t(NI_MAXHOST),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    ipString = String(cString: hostname)
                    break
                }
                if let next = ptr.pointee.ai_next {
                    ptr = next
                } else {
                    break
                }
            }
            continuation.resume(returning: ipString)
        }
    }
}

class SSLInfoFetcher: NSObject, URLSessionDelegate {
    private var continuation: CheckedContinuation<Date?, Error>?
    private var session: URLSession?
    
    func fetchExpiry(for host: String) async throws -> Date? {
        let cleanHost = host.replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .init(charactersIn: "/ "))
        
        guard let url = URL(string: "https://\(cleanHost)") else {
            throw NSError(domain: "SSLError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid host"])
        }
        
        self.session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let task = session?.dataTask(with: url) { _, _, error in
                if let error = error {
                    let nsError = error as NSError
                    // If we cancelled manually after getting the cert, don't throw
                    if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                        return
                    }
                    self.continuation?.resume(throwing: error)
                    self.continuation = nil
                }
            }
            task?.resume()
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if let serverTrust = challenge.protectionSpace.serverTrust {
            // Get the certificate from the trust
            if let cert = SecTrustGetCertificateAtIndex(serverTrust, 0) {
                let data = SecCertificateCopyData(cert) as Data
                if let expiryDate = extractExpiryDate(from: data) {
                    continuation?.resume(returning: expiryDate)
                    continuation = nil
                    session.invalidateAndCancel()
                    completionHandler(.cancelAuthenticationChallenge, nil)
                    return
                }
            }
        }
        
        // If we reach here, we couldn't find the date
        continuation?.resume(throwing: NSError(domain: "SSLError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not extract expiration date from certificate"]))
        continuation = nil
        session.invalidateAndCancel()
        completionHandler(.cancelAuthenticationChallenge, nil)
    }
    
    /// A simple DER parser to extract the expiration date (Not After) from a certificate.
    /// In X.509, the validity period is a sequence of two dates (notBefore and notAfter).
    /// These are typically the first two UTCTime (0x17) or GeneralizedTime (0x18) tags in the certificate data.
    private func extractExpiryDate(from data: Data) -> Date? {
        var dates: [Date] = []
        var offset = 0
        let bytes = [UInt8](data)
        
        while offset < bytes.count - 1 {
            let tag = bytes[offset]
            if tag == 0x17 || tag == 0x18 { // UTCTime or GeneralizedTime
                let length = Int(bytes[offset + 1])
                if offset + 2 + length <= bytes.count {
                    let dateData = data.subdata(in: (offset + 2)..<(offset + 2 + length))
                    if let dateString = String(data: dateData, encoding: .ascii) {
                        let formatter = DateFormatter()
                        formatter.calendar = Calendar(identifier: .gregorian)
                        formatter.timeZone = TimeZone(secondsFromGMT: 0)
                        
                        if tag == 0x17 {
                            formatter.dateFormat = "yyMMddHHmmss'Z'"
                        } else {
                            formatter.dateFormat = "yyyyMMddHHmmss'Z'"
                        }
                        
                        if let date = formatter.date(from: dateString) {
                            dates.append(date)
                        }
                    }
                    offset += 2 + length
                    continue
                }
            }
            offset += 1
        }
        
        // The expiration date (Not After) is the second date in the validity period.
        // In a typical certificate, these are the first two dates found.
        if dates.count >= 2 {
            return dates[1]
        }
        return dates.first // Fallback to first if only one found (unlikely but safer)
    }
}
