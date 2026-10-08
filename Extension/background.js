// McDownloader browser bridge.
//
// Two jobs:
//   1. Intercept browser downloads and hand them to the McDownloader app,
//      carrying cookies and the referer so signed/logged-in URLs keep working.
//   2. Provide a "Download with McDownloader" and "Refresh link" action for the
//      current page or a clicked link, so an expired transfer can be re-seeded
//      with a fresh address.
//
// It talks to the app over a Native Messaging host: the browser launches our
// host program, which forwards to the app's local bridge. There is no port to
// set and no token to copy. If the host is not installed (older setups), it
// falls back to the local HTTP bridge using a port and token from Options.

const HOST_NAME = "io.github.zakiyys.mcdownloader";

const DEFAULTS = { port: 6847, token: "", intercept: true, enabled: true };

async function getConfig() {
  const stored = await chrome.storage.local.get(DEFAULTS);
  return { ...DEFAULTS, ...stored };
}

function endpoint(config) {
  return `http://127.0.0.1:${config.port}`;
}

// 1. Native messaging (preferred) -------------------------------------------

/** Sends one message to the app through the native host. */
function sendViaNative(payload) {
  return new Promise((resolve) => {
    let port;
    try {
      port = chrome.runtime.connectNative(HOST_NAME);
    } catch (error) {
      resolve({ ok: false, reason: "native-unavailable" });
      return;
    }

    const done = (result) => {
      try { port.disconnect(); } catch { /* already gone */ }
      resolve(result);
    };

    port.onMessage.addListener((response) => done(response || { ok: true }));
    port.onDisconnect.addListener(() => {
      const lastError = chrome.runtime.lastError;
      if (lastError) done({ ok: false, reason: "native-unavailable" });
    });

    try {
      port.postMessage(payload);
    } catch (error) {
      done({ ok: false, reason: "native-unavailable" });
    }
  });
}

// 2. Local HTTP bridge (fallback) -------------------------------------------

async function appStatus(config) {
  try {
    const response = await fetch(`${endpoint(config)}/ping`, { cache: "no-store" });
    return response.ok;
  } catch {
    return false;
  }
}

async function sendViaHTTP(payload, config) {
  const response = await fetch(`${endpoint(config)}/add`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-McDownloader-Token": config.token },
    body: JSON.stringify(payload)
  });
  if (!response.ok) {
    const text = await response.text().catch(() => "");
    throw new Error(text || `HTTP ${response.status}`);
  }
  return response.json();
}

/** Collects cookies for a URL as a single Cookie header value. */
async function cookieHeaderFor(url) {
  try {
    const cookies = await chrome.cookies.getAll({ url });
    return cookies.map((c) => `${c.name}=${c.value}`).join("; ");
  } catch {
    return "";
  }
}

function filenameFromUrl(url) {
  try {
    const parsed = new URL(url);
    const last = parsed.pathname.split("/").filter(Boolean).pop() || "";
    return decodeURIComponent(last);
  } catch {
    return "";
  }
}

async function notify(message) {
  try {
    await chrome.notifications.create({
      type: "basic",
      iconUrl: "icons/icon-128.png",
      title: "McDownloader",
      message
    });
  } catch {
    // Notifications are best-effort.
  }
}

/** Is the app reachable, natively or over the bridge? */
async function isAppRunning(config) {
  const native = await sendViaNative({ type: "ping" });
  if (native.ok) return { running: true, transport: "native" };
  return { running: await appStatus(config), transport: "http" };
}

/** Sends a link to the app, attaching cookies and referer. */
async function handOff(url, referer) {
  const config = await getConfig();
  if (!config.enabled) return { ok: false, reason: "disabled" };

  const payload = {
    url,
    referer: referer || "",
    cookie: await cookieHeaderFor(url),
    filename: filenameFromUrl(url)
  };

  // Prefer the native host; fall back to the HTTP bridge.
  const native = await sendViaNative(payload);
  if (native.ok) return { ok: true, transport: "native" };
  if (native.reason && native.reason !== "native-unavailable") return native;

  if (!(await appStatus(config))) return { ok: false, reason: "app-not-running" };
  try {
    await sendViaHTTP(payload, config);
    return { ok: true, transport: "http" };
  } catch (error) {
    return { ok: false, reason: error.message };
  }
}

// 3. Download interception ---------------------------------------------------

chrome.downloads.onDeterminingFilename.addListener((item, suggest) => {
  (async () => {
    const config = await getConfig();
    if (!config.intercept || !config.enabled) {
      suggest();
      return;
    }
    const result = await handOff(item.url, item.referrer);
    if (result.ok) {
      chrome.downloads.cancel(item.id, () => chrome.downloads.erase({ id: item.id }));
      suggest();
    } else {
      // Let the browser handle it if the app is not there.
      suggest();
    }
  })();
  return true;
});

// 4. Context menus -----------------------------------------------------------

chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({
    id: "mcd-link",
    title: "Download with McDownloader",
    contexts: ["link"]
  });
  chrome.contextMenus.create({
    id: "mcd-page",
    title: "Download this page with McDownloader",
    contexts: ["page"]
  });
  chrome.contextMenus.create({
    id: "mcd-media",
    title: "Download this media with McDownloader",
    contexts: ["video", "audio", "image"]
  });
});

chrome.contextMenus.onClicked.addListener(async (info) => {
  const url = info.linkUrl || info.srcUrl || info.pageUrl;
  if (!url) return;
  const result = await handOff(url, info.pageUrl);
  if (!result.ok) {
    await notify(
      result.reason === "app-not-running"
        ? "McDownloader is not running."
        : `Could not add the link: ${result.reason}`
    );
  }
});

// 5. Messages from the popup -------------------------------------------------

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  (async () => {
    switch (message.type) {
      case "status": {
        const config = await getConfig();
        const state = await isAppRunning(config);
        sendResponse({
          running: state.running,
          transport: state.transport,
          port: state.transport === "http" ? config.port : null
        });
        break;
      }
      case "add": {
        const result = await handOff(message.url, message.referer);
        sendResponse(result);
        break;
      }
      case "test": {
        const config = await getConfig();
        const state = await isAppRunning(config);
        sendResponse({ running: state.running, transport: state.transport, port: config.port });
        break;
      }
      default:
        sendResponse({ ok: false, reason: "unknown message" });
    }
  })();
  return true;
});
