import Foundation

/// Minimal HTTP/1.1 request parser: request line, headers (lowercased), body by Content-Length.
struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var h: [String: String] = [:]
        for l in lines {
            guard let i = l.firstIndex(of: ":") else { continue }
            h[l[..<i].lowercased()] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(h["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(first[0]); path = String(first[1]); headers = h
        body = data.subdata(in: bodyStart..<(bodyStart + length))
    }
}
