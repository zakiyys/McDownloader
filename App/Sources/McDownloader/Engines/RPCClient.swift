import Foundation

enum EngineError: LocalizedError {
    case notRunning
    case rpc(String)
    case unreachable(String)
    case badResponse(String)
    case fileMissing(String)

    var errorDescription: String? {
        switch self {
        case .notRunning: return "The download engine is not running."
        case .rpc(let m): return "Engine rejected the request: \(m)"
        case .unreachable(let m): return "Cannot reach the engine at \(m)."
        case .badResponse(let m): return "Unexpected response from the engine: \(m)"
        case .fileMissing(let p): return "File not found: \(p)"
        }
    }
}

/// Minimal JSON-RPC 2.0 client over HTTP. Used for aria2 and the torrent helper.
/// Both speak the same envelope, so one client serves both engines.
struct RPCClient {
    let endpoint: URL
    let secret: String?

    func call(_ method: String, params: [Any] = [], timeout: TimeInterval = 8) async throws -> Any {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var finalParams = params
        if let secret { finalParams.insert("token:\(secret)", at: 0) }

        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": finalParams
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw EngineError.badResponse("no HTTP response")
            }
            guard http.statusCode == 200 else {
                throw EngineError.badResponse("HTTP \(http.statusCode)")
            }
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw EngineError.badResponse(String(data: data, encoding: .utf8) ?? "binary")
            }
            if let error = object["error"] as? [String: Any] {
                throw EngineError.rpc(error["message"] as? String ?? "unknown error")
            }
            return object["result"] ?? NSNull()
        } catch let urlError as URLError {
            throw EngineError.unreachable("\(endpoint.host ?? "localhost"):\(endpoint.port ?? 0) (\(urlError.localizedDescription))")
        }
    }
}

/// Decoding helpers for the loosely-typed JSON aria2 and libtorrent return.
extension Dictionary where Key == String, Value == Any {
    func string(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let n = self[key] as? NSNumber { return n.stringValue }
        return nil
    }

    func int(_ key: String) -> Int? {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func int64(_ key: String) -> Int64? {
        if let n = self[key] as? NSNumber { return n.int64Value }
        if let s = self[key] as? String { return Int64(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let n = self[key] as? NSNumber { return n.boolValue }
        if let s = self[key] as? String { return (s as NSString).boolValue }
        return nil
    }

    func array(_ key: String) -> [[String: Any]]? {
        self[key] as? [[String: Any]]
    }
}
