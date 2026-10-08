import Foundation

// McDownloader native messaging host.
//
// A Chromium browser launches this small program when the extension calls
// `chrome.runtime.connectNative("io.github.zakiyys.mcdownloader")`. It speaks
// the browser's stdio framing (a 4-byte little-endian length, then that many
// bytes of UTF-8 JSON) on stdin/stdout, and forwards every message to the app's
// local HTTP bridge.
//
// Because the browser already gates who may launch it (the host manifest's
// allowed_origins), this program does not need the user to copy a token: it
// reads the app's own config to find the bridge port and token. The token still
// authenticates the request to the bridge; the user just never sees it.

// MARK: - Config (mirrors the app's, read-only)

struct BridgeConfig {
    var port: Int
    var token: String
}

func readBridgeConfig() -> BridgeConfig {
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("McDownloader", isDirectory: true)
    let configURL = support.appendingPathComponent("config.json")
    guard let data = try? Data(contentsOf: configURL),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return BridgeConfig(port: 6847, token: "")
    }
    return BridgeConfig(
        port: object["browserBridgePort"] as? Int ?? 6847,
        token: object["browserBridgeToken"] as? String ?? ""
    )
}

// MARK: - Stdio framing

func readExactly(_ handle: FileHandle, count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        let chunk = handle.readData(ofLength: count - data.count)
        if chunk.isEmpty { return data.isEmpty ? nil : data }
        data.append(chunk)
    }
    return data
}

func readMessage() -> [String: Any]? {
    let stdin = FileHandle.standardInput
    guard let header = readExactly(stdin, count: 4), header.count == 4 else { return nil }
    let bytes = [UInt8](header)
    // Chrome frames the length as a 4-byte little-endian unsigned integer.
    let length = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
    guard length > 0, length <= 8 * 1024 * 1024, let body = readExactly(stdin, count: Int(length)) else { return nil }
    return (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
}

func writeMessage(_ object: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: object) else { return }
    let count = UInt32(body.count)
    let header = Data([
        UInt8(count & 0xff),
        UInt8((count >> 8) & 0xff),
        UInt8((count >> 16) & 0xff),
        UInt8((count >> 24) & 0xff)
    ])
    FileHandle.standardOutput.write(header)
    FileHandle.standardOutput.write(body)
}

// MARK: - Forwarding to the app bridge

func post(_ payload: [String: Any], to config: BridgeConfig) -> [String: Any] {
    guard let url = URL(string: "http://127.0.0.1:\(config.port)/add") else {
        return ["ok": false, "reason": "bad-app-url"]
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue(config.token, forHTTPHeaderField: "X-McDownloader-Token")
    request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

    let semaphore = DispatchSemaphore(value: 0)
    var result: [String: Any] = ["ok": false, "reason": "app-not-running"]
    URLSession.shared.dataTask(with: request) { data, response, error in
        defer { semaphore.signal() }
        if error != nil { result = ["ok": false, "reason": "app-not-running"]; return }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 {
            result = ["ok": true]
        } else if status == 401 {
            result = ["ok": false, "reason": "bad-token"]
        } else {
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            result = ["ok": false, "reason": text.isEmpty ? "HTTP \(status)" : text]
        }
    }.resume()
    semaphore.wait()

    // Nudge the app to the front so the new transfer is visible.
    if result["ok"] as? Bool == true {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-b", "io.github.zakiyys.McDownloader"]
        try? task.run()
    }
    return result
}

func handle(_ message: [String: Any]) -> [String: Any] {
    // The extension may send either a bare payload or {type, ...}.
    var payload = message
    if let type = message["type"] as? String, type == "ping" {
        return ["ok": true, "app": "McDownloader", "host": "mcdownloader-host"]
    }
    payload.removeValue(forKey: "type")
    let config = readBridgeConfig()
    return post(payload, to: config)
}

// MARK: - Main loop

while let message = readMessage() {
    writeMessage(handle(message))
}
