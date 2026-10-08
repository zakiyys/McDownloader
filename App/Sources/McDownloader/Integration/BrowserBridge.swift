import Foundation
import Network

/// A tiny localhost HTTP server the browser extension talks to. It listens on
/// 127.0.0.1 only, requires a per-install bearer token, and accepts exactly two
/// routes: `GET /ping` (does the app exist?) and `POST /add` (enqueue a link).
///
/// The extension posts here rather than to aria2 directly so queueing,
/// categories, destination folders and the cookie/referer headers all stay under
/// one roof. No native messaging host is needed, which is what keeps the
/// Manifest V3 path simple.
final class BrowserBridge {
    private var listener: NWListener?
    private let port: Int
    private let token: String
    private let queue = DispatchQueue(label: "io.github.zakiyys.McDownloader.bridge")

    private(set) var isRunning = false
    var onAdd: ((AddRequest) -> Void)?
    var onPing: (() -> Void)?

    init(port: Int, token: String) {
        self.port = port
        self.token = token
    }

    func start() {
        guard !isRunning else { return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: UInt16(port))!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    Log.error("browser bridge listener failed: \(error.localizedDescription)")
                }
            }
            listener.start(queue: queue)
            self.listener = listener
            isRunning = true
            Log.info("browser bridge listening on 127.0.0.1:\(port)")
        } catch {
            Log.error("browser bridge could not start: \(error.localizedDescription)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: Connection handling

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var accumulated = buffer
            if let data { accumulated.append(data) }

            if let request = HTTPRequest.parse(accumulated) {
                let response = self.respond(to: request)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            if isComplete || error != nil || accumulated.count > 1_048_576 {
                connection.cancel()
                return
            }
            self.receive(on: connection, buffer: accumulated)
        }
    }

    private func respond(to request: HTTPRequest) -> Data {
        switch (request.method, request.path) {
        case ("GET", "/ping"):
            onPing?()
            return HTTPResponse.json(status: 200, body: ["app": "McDownloader", "version": appVersion])
        case ("POST", "/add"):
            guard request.header("x-mcdownloader-token") == token else {
                return HTTPResponse.json(status: 401, body: ["error": "bad token"])
            }
            guard let body = request.json() else {
                return HTTPResponse.json(status: 400, body: ["error": "invalid JSON body"])
            }
            let addRequest = AddRequest.url(
                body["url"] as? String ?? "",
                referer: body["referer"] as? String,
                cookie: body["cookie"] as? String,
                userAgent: body["userAgent"] as? String,
                filename: body["filename"] as? String,
                savePath: body["savePath"] as? String
            )
            onAdd?(addRequest)
            return HTTPResponse.json(status: 200, body: ["ok": true])
        case ("OPTIONS", _):
            return HTTPResponse.preflight()
        default:
            return HTTPResponse.json(status: 404, body: ["error": "not found"])
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}

// MARK: - Minimal HTTP parsing

struct HTTPRequest {
    var method: String
    var path: String
    var headers: [String: String]
    var body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    func json() -> [String: Any]? {
        body.isEmpty ? nil : (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? nil
    }

    /// Parses a request if the full body has arrived; returns nil to keep reading.
    static func parse(_ data: Data) -> HTTPRequest? {
        guard let range = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<range.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = range.upperBound
        let available = data.count - bodyStart
        if available < contentLength { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        return HTTPRequest(method: method, path: path, headers: headers, body: body)
    }
}

enum HTTPResponse {
    static func json(status: Int, body: [String: Any]) -> Data {
        let payload = (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        return raw(status: status, contentType: "application/json", body: payload)
    }

    static func preflight() -> Data {
        let headers = [
            "HTTP/1.1 204 No Content",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type, X-McDownloader-Token",
            "Access-Control-Max-Age: 86400",
            "Content-Length: 0",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        return Data(headers.utf8)
    }

    private static func raw(status: Int, contentType: String, body: Data) -> Data {
        let reason = status == 200 ? "OK" : (status == 401 ? "Unauthorized" : (status == 400 ? "Bad Request" : "Not Found"))
        let header = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Content-Type, X-McDownloader-Token",
            "Connection: close",
            "", ""
        ].joined(separator: "\r\n")
        var data = Data(header.utf8)
        data.append(body)
        return data
    }
}
