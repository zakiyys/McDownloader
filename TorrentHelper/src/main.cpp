// mcdownloader-torrentd
//
// A small BitTorrent engine for McDownloader, built on libtorrent 2.x.
// It exposes a tiny JSON-RPC server on localhost that mirrors the shape of
// aria2's API, so the app talks to both engines the same way.
//
// Why a separate process: a crash in libtorrent cannot take the GUI down, and
// the C++ stays behind a process boundary instead of crossing into Swift.
//
// Routes (POST, JSON-RPC 2.0), all requiring the token as the first param:
//   torrent.version         -> { version }
//   torrent.list            -> [ status, ... ]
//   torrent.detail   [id]   -> { status, files, peers, trackers }
//   torrent.addMagnet[uri, opts]
//   torrent.addTorrent[path, opts]
//   torrent.pause    [id]
//   torrent.resume   [id]
//   torrent.remove   [id, opts]
//   torrent.pauseAll
//   torrent.resumeAll
//   torrent.setFileSelection[id, opts]
//   torrent.setLimits[opts]

#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/peer_info.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/error_code.hpp>
#include <libtorrent/info_hash.hpp>
#include <libtorrent/sha1_hash.hpp>
#include <libtorrent/version.hpp>
#include <libtorrent/write_resume_data.hpp>
#include <libtorrent/read_resume_data.hpp>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

namespace fs = std::filesystem;
using namespace std::chrono_literals;

// ---------------------------------------------------------------------------
// Minimal JSON building and parsing. No third-party dependency, which keeps the
// universal build simple.
// ---------------------------------------------------------------------------

static std::string jsonEscape(const std::string& in) {
    std::string out;
    out.reserve(in.size() + 8);
    for (unsigned char c : in) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    std::snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += static_cast<char>(c);
                }
        }
    }
    return out;
}

static std::string jstr(const std::string& s) { return "\"" + jsonEscape(s) + "\""; }
static std::string jnum(int64_t v) { return std::to_string(v); }
static std::string jnum(double v) {
    std::ostringstream os;
    os << v;
    return os.str();
}
static std::string jbool(bool v) { return v ? "true" : "false"; }

// A very small JSON value reader, enough for our request bodies.
struct JsonValue {
    enum Type { Null, Bool, Number, String, Array, Object } type = Null;
    bool boolean = false;
    double number = 0;
    std::string str;
    std::vector<JsonValue> array;
    std::map<std::string, JsonValue> object;

    const JsonValue* get(const std::string& key) const {
        auto it = object.find(key);
        return it == object.end() ? nullptr : &it->second;
    }
    std::string asString(const std::string& fallback = "") const {
        return type == String ? str : fallback;
    }
    int64_t asInt(int64_t fallback = 0) const {
        return type == Number ? static_cast<int64_t>(number) : fallback;
    }
    bool asBool(bool fallback = false) const {
        return type == Bool ? boolean : fallback;
    }
};

static void skipWs(const std::string& s, size_t& i) {
    while (i < s.size() && std::isspace(static_cast<unsigned char>(s[i]))) i++;
}

static JsonValue parseJson(const std::string& s, size_t& i);

static std::string parseString(const std::string& s, size_t& i) {
    std::string out;
    i++; // opening quote
    while (i < s.size() && s[i] != '"') {
        if (s[i] == '\\' && i + 1 < s.size()) {
            char c = s[i + 1];
            switch (c) {
                case 'n': out += '\n'; break;
                case 't': out += '\t'; break;
                case 'r': out += '\r'; break;
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                default: out += c;
            }
            i += 2;
        } else {
            out += s[i++];
        }
    }
    i++; // closing quote
    return out;
}

static JsonValue parseJson(const std::string& s, size_t& i) {
    skipWs(s, i);
    JsonValue v;
    if (i >= s.size()) return v;
    char c = s[i];
    if (c == '{') {
        v.type = JsonValue::Object;
        i++;
        while (i < s.size() && s[i] != '}') {
            skipWs(s, i);
            if (s[i] == '}') break;
            std::string key = parseString(s, i);
            skipWs(s, i);
            if (s[i] == ':') i++;
            v.object[key] = parseJson(s, i);
            skipWs(s, i);
            if (s[i] == ',') i++;
        }
        i++;
    } else if (c == '[') {
        v.type = JsonValue::Array;
        i++;
        while (i < s.size() && s[i] != ']') {
            v.array.push_back(parseJson(s, i));
            skipWs(s, i);
            if (s[i] == ',') i++;
        }
        i++;
    } else if (c == '"') {
        v.type = JsonValue::String;
        v.str = parseString(s, i);
    } else if (c == 't' || c == 'f') {
        v.type = JsonValue::Bool;
        v.boolean = (c == 't');
        i += v.boolean ? 4 : 5;
    } else if (c == 'n') {
        v.type = JsonValue::Null;
        i += 4;
    } else {
        v.type = JsonValue::Number;
        size_t start = i;
        while (i < s.size() && (std::isdigit(static_cast<unsigned char>(s[i])) || s[i] == '-' || s[i] == '+' || s[i] == '.' || s[i] == 'e' || s[i] == 'E')) i++;
        v.number = std::stod(s.substr(start, i - start));
    }
    return v;
}

// ---------------------------------------------------------------------------
// Engine state
// ---------------------------------------------------------------------------

struct Engine {
    std::unique_ptr<lt::session> session;
    std::string secret;
    std::string savePath;
    std::string stateDir;
    bool seed = true;
    double ratioLimit = 1.0;
    int timeLimitMinutes = 60;
    int listenPort = 6881;
    std::mutex mutex; // guards libtorrent calls from the HTTP and maintenance threads
    std::map<std::string, fs::file_time_type> knownMtime; // id -> .torrent file mtime
};

static Engine g_engine;

static std::string hashHex(const lt::sha1_hash& h) {
    return h.to_hex();
}

static std::string torrentId(const lt::torrent_handle& h) {
    return hashHex(h.info_hashes().get_best());
}

static std::string stateFromStatus(const lt::torrent_status& st) {
    switch (st.state) {
        case lt::torrent_status::queued_for_checking: return "queued";
        case lt::torrent_status::checking_files: return "checking";
        case lt::torrent_status::downloading_metadata: return "meta";
        case lt::torrent_status::downloading: return "downloading";
        case lt::torrent_status::finished: return "completed";
        case lt::torrent_status::seeding: return "seeding";
        case lt::torrent_status::allocating: return "allocating";
        case lt::torrent_status::checking_resume_data: return "checking";
    }
    return "queued";
}

// Sample the piece bitfield down to at most `cells` cells so the UI can draw a
// band without shipping thousands of booleans over the wire.
static std::string piecesJson(const lt::torrent_status& st, int cells = 160) {
    std::string out = "[";
    int total = st.num_pieces;
    if (total <= 0) return "[]";
    int step = std::max(1, total / cells);
    bool first = true;
    for (int i = 0; i < total; i += step) {
        bool done = st.pieces.get_bit(i);
        if (!first) out += ",";
        out += done ? "1" : "0";
        first = false;
    }
    out += "]";
    return out;
}

static std::string statusJson(const lt::torrent_handle& h) {
    lt::torrent_status st = h.status();
    std::string name = st.name.empty() ? torrentId(h) : st.name;

    std::string savePathOut;
    try { savePathOut = h.status(lt::torrent_handle::query_save_path).save_path; } catch (...) {}

    std::string out = "{";
    out += jstr("id") + ":" + jstr(torrentId(h)) + ",";
    out += jstr("infoHash") + ":" + jstr(torrentId(h)) + ",";
    out += jstr("name") + ":" + jstr(name) + ",";
    out += jstr("state") + ":" + jstr(stateFromStatus(st)) + ",";
    out += jstr("totalBytes") + ":" + jnum(static_cast<int64_t>(st.total_wanted)) + ",";
    out += jstr("completedBytes") + ":" + jnum(static_cast<int64_t>(st.total_wanted_done)) + ",";
    out += jstr("downloadSpeed") + ":" + jnum(static_cast<int64_t>(st.download_rate)) + ",";
    out += jstr("uploadSpeed") + ":" + jnum(static_cast<int64_t>(st.upload_rate)) + ",";
    out += jstr("uploadedBytes") + ":" + jnum(static_cast<int64_t>(st.total_upload)) + ",";
    out += jstr("peersConnected") + ":" + jnum(static_cast<int64_t>(st.num_peers)) + ",";
    out += jstr("seeders") + ":" + jnum(static_cast<int64_t>(st.num_seeds)) + ",";
    out += jstr("leechers") + ":" + jnum(static_cast<int64_t>(std::max(0, st.num_peers - st.num_seeds))) + ",";
    out += jstr("ratio") + ":" + jnum(st.all_time_upload > 0 && st.all_time_download > 0
                                        ? static_cast<double>(st.all_time_upload) / static_cast<double>(st.all_time_download)
                                        : 0.0) + ",";
    out += jstr("savePath") + ":" + jstr(savePathOut.empty() ? g_engine.savePath : savePathOut) + ",";
    out += jstr("targetPath") + ":" + jstr(savePathOut.empty() ? g_engine.savePath : savePathOut) + ",";
    out += jstr("pieces") + ":" + piecesJson(st);
    out += "}";
    return out;
}

static std::string detailJson(const lt::torrent_handle& h) {
    std::string out = statusJson(h);
    // Strip the closing brace so we can append detail fields.
    out.pop_back();

    // Files
    std::string files = "[";
    auto ti = h.torrent_file();
    if (ti) {
        std::vector<int64_t> progress;
        try { progress = h.file_progress(lt::torrent_handle::piece_granularity); } catch (...) {}
        auto& storage = ti->files();
        bool first = true;
        for (int i = 0; i < storage.num_files(); ++i) {
            if (!first) files += ",";
            files += "{";
            files += jstr("index") + ":" + jnum(i) + ",";
            files += jstr("path") + ":" + jstr(storage.file_path(i)) + ",";
            files += jstr("length") + ":" + jnum(static_cast<int64_t>(storage.file_size(i))) + ",";
            int64_t done = (static_cast<size_t>(i) < progress.size()) ? progress[i] : 0;
            files += jstr("completed") + ":" + jnum(done) + ",";
            bool selected = h.file_priority(i) != lt::dont_download;
            files += jstr("selected") + ":" + jbool(selected);
            files += "}";
            first = false;
        }
    }
    files += "]";
    out += "," + jstr("files") + ":" + files;

    // Peers
    std::string peers = "[";
    try {
        std::vector<lt::peer_info> plist = h.get_peer_info();
        bool first = true;
        for (auto& p : plist) {
            if (!first) peers += ",";
            peers += "{";
            peers += jstr("address") + ":" + jstr(p.ip.to_string()) + ",";
            peers += jstr("port") + ":" + jnum(static_cast<int64_t>(p.port)) + ",";
            peers += jstr("client") + ":" + jstr(p.client) + ",";
            peers += jstr("downloadSpeed") + ":" + jnum(static_cast<int64_t>(p.down_speed)) + ",";
            peers += jstr("uploadSpeed") + ":" + jnum(static_cast<int64_t>(p.up_speed)) + ",";
            peers += jstr("progress") + ":" + jnum(static_cast<double>(p.progress)) + ",";
            peers += jstr("flags") + ":" + jstr(std::string(p.flags.to_string()));
            peers += "}";
            first = false;
        }
    } catch (...) {}
    peers += "]";
    out += "," + jstr("peers") + ":" + peers;

    // Trackers
    std::string trackers = "[";
    try {
        std::vector<lt::announce_entry> tlist = h.trackers();
        bool first = true;
        for (auto& t : tlist) {
            if (!first) trackers += ",";
            std::string message;
            bool working = false;
            if (!t.endpoints.empty()) {
                message = t.endpoints.front().message;
                working = !t.endpoints.front().info_hashes.empty();
            }
            trackers += "{";
            trackers += jstr("url") + ":" + jstr(t.url) + ",";
            trackers += jstr("message") + ":" + jstr(message) + ",";
            trackers += jstr("seeders") + ":0,";
            trackers += jstr("leechers") + ":0,";
            trackers += jstr("working") + ":" + jbool(working);
            trackers += "}";
            first = false;
        }
    } catch (...) {}
    trackers += "]";
    out += "," + jstr("trackers") + ":" + trackers;

    out += "}";
    return out;
}

// ---------------------------------------------------------------------------
// Command handling
// ---------------------------------------------------------------------------

struct RpcRequest {
    std::string method;
    std::vector<JsonValue> params;
    std::string id;
};

static std::string okResponse(const std::string& id, const std::string& result) {
    return "{\"jsonrpc\":\"2.0\",\"id\":" + jstr(id) + ",\"result\":" + result + "}";
}

static std::string errorResponse(const std::string& id, const std::string& message) {
    return "{\"jsonrpc\":\"2.0\",\"id\":" + jstr(id) + ",\"error\":{\"code\":-32000,\"message\":" + jstr(message) + "}}";
}

static lt::torrent_handle* findHandle(const std::string& id) {
    auto handles = g_engine.session->get_torrents();
    for (auto& h : handles) {
        if (torrentId(h) == id) return new lt::torrent_handle(h);
    }
    return nullptr;
}
// (findHandle exists for symmetry with other RPC servers; lookups below are
// done inline to keep the hot path free of allocations.)

static void applySessionLimits(int64_t down, int64_t up) {
    lt::settings_pack sp;
    sp.set_int(lt::settings_pack::download_rate_limit, static_cast<int>(down));
    sp.set_int(lt::settings_pack::upload_rate_limit, static_cast<int>(up));
    g_engine.session->apply_settings(sp);
}

static std::string handleCommand(const RpcRequest& req) {
    std::lock_guard<std::mutex> lock(g_engine.mutex);

    // Token check: first param must be "token:<secret>".
    if (req.params.empty() || req.params[0].asString() != ("token:" + g_engine.secret)) {
        return errorResponse(req.id, "invalid token");
    }
    std::vector<JsonValue> args(req.params.begin() + 1, req.params.end());

    if (req.method == "torrent.version") {
        return okResponse(req.id, "{\"version\":" + jstr(lt::version()) + ",\"api\":\"libtorrent\"}");
    }

    if (req.method == "torrent.list") {
        std::string out = "[";
        bool first = true;
        for (auto& h : g_engine.session->get_torrents()) {
            if (!first) out += ",";
            out += statusJson(h);
            first = false;
        }
        out += "]";
        return okResponse(req.id, out);
    }

    if (req.method == "torrent.detail") {
        if (args.empty()) return errorResponse(req.id, "missing id");
        for (auto& h : g_engine.session->get_torrents()) {
            if (torrentId(h) == args[0].asString()) {
                return okResponse(req.id, detailJson(h));
            }
        }
        return errorResponse(req.id, "torrent not found");
    }

    if (req.method == "torrent.addMagnet") {
        if (args.empty()) return errorResponse(req.id, "missing magnet");
        std::string uri = args[0].asString();
        std::string savePath = g_engine.savePath;
        if (args.size() > 1 && args[1].get("save_path")) savePath = args[1].get("save_path")->asString(savePath);

        lt::error_code ec;
        lt::add_torrent_params p = lt::parse_magnet_uri(uri, ec);
        if (ec) return errorResponse(req.id, "bad magnet: " + ec.message());
        p.save_path = savePath;
        lt::torrent_handle h = g_engine.session->add_torrent(p, ec);
        if (ec) return errorResponse(req.id, ec.message());
        return okResponse(req.id, jstr(torrentId(h)));
    }

    if (req.method == "torrent.addTorrent") {
        if (args.empty()) return errorResponse(req.id, "missing path");
        std::string path = args[0].asString();
        std::string savePath = g_engine.savePath;
        if (args.size() > 1 && args[1].get("save_path")) savePath = args[1].get("save_path")->asString(savePath);

        lt::error_code ec;
        auto ti = std::make_shared<lt::torrent_info>(path, ec);
        if (ec) return errorResponse(req.id, "bad torrent file: " + ec.message());
        lt::add_torrent_params p;
        p.ti = ti;
        p.save_path = savePath;
        lt::torrent_handle h = g_engine.session->add_torrent(p, ec);
        if (ec) return errorResponse(req.id, ec.message());
        return okResponse(req.id, jstr(torrentId(h)));
    }

    if (req.method == "torrent.pause" || req.method == "torrent.resume") {
        if (args.empty()) return errorResponse(req.id, "missing id");
        for (auto& h : g_engine.session->get_torrents()) {
            if (torrentId(h) == args[0].asString()) {
                if (req.method == "torrent.pause") h.pause(); else h.resume();
                return okResponse(req.id, "true");
            }
        }
        return errorResponse(req.id, "torrent not found");
    }

    if (req.method == "torrent.remove") {
        if (args.empty()) return errorResponse(req.id, "missing id");
        bool deleteFiles = false;
        if (args.size() > 1 && args[1].get("delete_files")) deleteFiles = args[1].get("delete_files")->asBool();
        for (auto& h : g_engine.session->get_torrents()) {
            if (torrentId(h) == args[0].asString()) {
                g_engine.session->remove_torrent(h, deleteFiles ? lt::session::delete_files : 0);
                return okResponse(req.id, "true");
            }
        }
        return errorResponse(req.id, "torrent not found");
    }

    if (req.method == "torrent.pauseAll" || req.method == "torrent.resumeAll") {
        for (auto& h : g_engine.session->get_torrents()) {
            if (req.method == "torrent.pauseAll") h.pause(); else h.resume();
        }
        return okResponse(req.id, "true");
    }

    if (req.method == "torrent.setFileSelection") {
        if (args.size() < 2) return errorResponse(req.id, "missing args");
        std::string id = args[0].asString();
        std::vector<int> wanted;
        if (const JsonValue* files = args[1].get("files")) {
            for (auto& v : files->array) wanted.push_back(static_cast<int>(v.asInt()));
        }
        for (auto& h : g_engine.session->get_torrents()) {
            if (torrentId(h) == id) {
                auto ti = h.torrent_file();
                if (!ti) return errorResponse(req.id, "metadata not ready");
                std::vector<lt::download_priority_t> prio(ti->files().num_files(), lt::dont_download);
                for (int index : wanted) {
                    if (index >= 0 && static_cast<size_t>(index) < prio.size()) prio[index] = lt::default_priority;
                }
                h.prioritize_files(prio);
                return okResponse(req.id, "true");
            }
        }
        return errorResponse(req.id, "torrent not found");
    }

    if (req.method == "torrent.setLimits") {
        int64_t down = 0, up = 0;
        if (!args.empty()) {
            if (const JsonValue* d = args[0].get("download")) down = d->asInt();
            if (const JsonValue* u = args[0].get("upload")) up = u->asInt();
        }
        applySessionLimits(down, up);
        return okResponse(req.id, "true");
    }

    return errorResponse(req.id, "unknown method: " + req.method);
}

// ---------------------------------------------------------------------------
// HTTP server (localhost only)
// ---------------------------------------------------------------------------

static std::string readRequest(int fd) {
    std::string data;
    char buffer[4096];
    size_t headerEnd = std::string::npos;
    size_t contentLength = 0;
    while (true) {
        ssize_t n = ::recv(fd, buffer, sizeof(buffer), 0);
        if (n <= 0) break;
        data.append(buffer, static_cast<size_t>(n));
        if (headerEnd == std::string::npos) {
            headerEnd = data.find("\r\n\r\n");
            if (headerEnd != std::string::npos) {
                std::string headers = data.substr(0, headerEnd);
                std::string lower;
                lower.resize(headers.size());
                std::transform(headers.begin(), headers.end(), lower.begin(), ::tolower);
                size_t pos = lower.find("content-length:");
                if (pos != std::string::npos) {
                    size_t start = pos + 15;
                    size_t end = lower.find("\r\n", start);
                    contentLength = std::stoul(data.substr(start, end - start));
                }
            }
        }
        if (headerEnd != std::string::npos) {
            size_t bodyStart = headerEnd + 4;
            if (data.size() - bodyStart >= contentLength) break;
        }
        if (data.size() > 4 * 1024 * 1024) break;
    }
    if (headerEnd == std::string::npos) return "";
    return data.substr(headerEnd + 4, contentLength);
}

static void sendAll(int fd, const std::string& response) {
    const char* ptr = response.data();
    size_t remaining = response.size();
    while (remaining > 0) {
        ssize_t n = ::send(fd, ptr, remaining, 0);
        if (n <= 0) break;
        ptr += n;
        remaining -= static_cast<size_t>(n);
    }
}

static void serveConnection(int fd) {
    std::string body = readRequest(fd);
    std::string result;

    if (body.empty()) {
        result = errorResponse("null", "empty request");
    } else {
        size_t i = 0;
        JsonValue root = parseJson(body, i);
        RpcRequest req;
        req.id = root.get("id") ? (root.get("id")->type == JsonValue::String ? root.get("id")->str : "1") : "1";
        if (const JsonValue* m = root.get("method")) req.method = m->asString();
        if (const JsonValue* p = root.get("params")) req.params = p->array;
        result = handleCommand(req);
    }

    std::string http =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: " + std::to_string(result.size()) + "\r\n"
        "Connection: close\r\n\r\n" + result;
    sendAll(fd, http);
    ::close(fd);
}

// ---------------------------------------------------------------------------
// Maintenance: resume data, seeding limits, alerts
// ---------------------------------------------------------------------------

static void maintenanceLoop() {
    auto lastSave = std::chrono::steady_clock::now();
    while (true) {
        std::this_thread::sleep_for(1s);
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        g_engine.session->pop_alerts();

        // Enforce seeding limits.
        for (auto& h : g_engine.session->get_torrents()) {
            lt::torrent_status st = h.status();
            if (st.state == lt::torrent_status::seeding) {
                double ratio = st.all_time_download > 0
                    ? static_cast<double>(st.all_time_upload) / static_cast<double>(st.all_time_download)
                    : 0.0;
                bool ratioHit = g_engine.ratioLimit > 0 && ratio >= g_engine.ratioLimit;
                bool timeHit = g_engine.timeLimitMinutes > 0 && st.active_time >= g_engine.timeLimitMinutes * 60;
                if (!g_engine.seed || ratioHit || timeHit) {
                    h.pause();
                }
            }
        }

        // Periodically persist resume data so a restart keeps partial progress.
        auto now = std::chrono::steady_clock::now();
        if (now - lastSave >= 60s) {
            lastSave = now;
            for (auto& h : g_engine.session->get_torrents()) {
                if (h.status().has_metadata) h.save_resume_data(lt::torrent_handle::save_info_dict);
            }
        }
    }
}

static void alertLoop() {
    while (true) {
        std::this_thread::sleep_for(1s);
        std::lock_guard<std::mutex> lock(g_engine.mutex);
        std::vector<lt::alert*> alerts = g_engine.session->pop_alerts();
        for (lt::alert* alert : alerts) {
            if (auto* rd = lt::alert_cast<lt::save_resume_data_alert>(alert)) {
                auto buffer = lt::write_resume_data_buf(rd->params);
                std::string id = hashHex(rd->handle.info_hashes().get_best());
                fs::path path = fs::path(g_engine.stateDir) / (id + ".fastresume");
                std::ofstream out(path, std::ios::binary);
                out.write(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            } else if (auto* fe = lt::alert_cast<lt::file_completed_alert>(alert)) {
                (void)fe;
            }
        }
    }
}

static void loadResumeData() {
    std::error_code ec;
    if (!fs::exists(g_engine.stateDir, ec)) return;
    for (auto& entry : fs::directory_iterator(g_engine.stateDir, ec)) {
        if (entry.path().extension() != ".fastresume") continue;
        std::ifstream in(entry.path(), std::ios::binary);
        std::string bytes((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        if (bytes.empty()) continue;
        lt::error_code lec;
        lt::add_torrent_params p = lt::read_resume_data(bytes, lec);
        if (lec) continue;
        p.save_path = g_engine.savePath;
        g_engine.session->async_add_torrent(p);
    }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

static std::string argValue(int argc, char** argv, const std::string& key, const std::string& fallback) {
    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg.rfind(key + "=", 0) == 0) return arg.substr(key.size() + 1);
    }
    return fallback;
}

int main(int argc, char** argv) {
    int port = std::stoi(argValue(argc, argv, "--port", "6850"));
    g_engine.secret = argValue(argc, argv, "--secret", "");
    g_engine.savePath = argValue(argc, argv, "--save-path", ".");
    g_engine.stateDir = argValue(argc, argv, "--state-dir", ".");
    g_engine.seed = argValue(argc, argv, "--seed", "1") == "1";
    g_engine.ratioLimit = std::stod(argValue(argc, argv, "--ratio-limit", "1.0"));
    g_engine.timeLimitMinutes = std::stoi(argValue(argc, argv, "--time-limit", "60"));
    g_engine.listenPort = std::stoi(argValue(argc, argv, "--listen-port", "6881"));

    fs::create_directories(g_engine.stateDir);

    lt::settings_pack sp;
    sp.set_bool(lt::settings_pack::enable_dht, true);
    sp.set_bool(lt::settings_pack::enable_lsd, true);
    sp.set_bool(lt::settings_pack::enable_upnp, true);
    sp.set_bool(lt::settings_pack::enable_natpmp, true);
    sp.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:" + std::to_string(g_engine.listenPort));
    sp.set_int(lt::settings_pack::alert_mask,
               lt::alert_category::status | lt::alert_category::error | lt::alert_category::storage);
    sp.set_str(lt::settings_pack::user_agent, "McDownloader/" MCD_VERSION);

    g_engine.session = std::make_unique<lt::session>(sp);
    loadResumeData();

    std::thread(maintenanceLoop).detach();
    std::thread(alertLoop).detach();

    // Bind to loopback only. The helper is never reachable off the machine.
    int server = ::socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) { std::cerr << "socket failed\n"; return 1; }
    int yes = 1;
    ::setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(static_cast<uint16_t>(port));
    if (::bind(server, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) < 0) {
        std::cerr << "bind failed on 127.0.0.1:" << port << "\n";
        return 1;
    }
    ::listen(server, 16);
    std::cout << "torrentd listening on 127.0.0.1:" << port << std::endl;

    while (true) {
        int client = ::accept(server, nullptr, nullptr);
        if (client < 0) continue;
        std::thread(serveConnection, client).detach();
    }
    return 0;
}
