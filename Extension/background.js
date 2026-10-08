// McDownloader browser bridge.
//
// Two jobs:
//   1. Intercept browser downloads and hand them to the McDownloader app,
//      carrying cookies and the referer so signed/logged-in URLs keep working.
//   2. Provide a "Download with McDownloader" and "Refresh link" action for the
//      current page or a clicked link, so an expired transfer can be re-seeded
//      with a fresh address.
//
// It talks to the app over 127.0.0.1 only, authenticated with a token the user
// copies from the app's Settings, so no native messaging host is required.

const DEFAULTS = { port: 6847, token: "", intercept: true, enabled: true };

async function getConfig() {
  const stored = await chrome.storage.local.get(DEFAULTS);
  return { ...DEFAULTS, ...stored };
}

function endpoint(config) {
  return `http://127.0.0.1:${config.port}`;
}

async function appStatus(config) {
  try {
    const response = await fetch(`${endpoint(config)}/ping`, { cache: "no-store" });
    return response.ok;
  } catch {
    return false;
  }
}

async function sendToApp(payload, config) {
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

/** Sends a link to the app, attaching cookies and referer. */
async function handOff(url, referer) {
  const config = await getConfig();
  if (!config.enabled) return { ok: false, reason: "disabled" };
  if (!(await appStatus(config))) return { ok: false, reason: "app-not-running" };
  try {
    await sendToApp(
      {
        url,
        referer: referer || "",
        cookie: await cookieHeaderFor(url),
        filename: filenameFromUrl(url)
      },
      config
    );
    return { ok: true };
  } catch (error) {
    return { ok: false, reason: error.message };
  }
}

// 1. Download interception ---------------------------------------------------

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

// 2. Context menus -----------------------------------------------------------

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

// 3. Messages from the popup -------------------------------------------------

chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  (async () => {
    switch (message.type) {
      case "status": {
        const config = await getConfig();
        sendResponse({ running: await appStatus(config), port: config.port });
        break;
      }
      case "add": {
        const result = await handOff(message.url, message.referer);
        sendResponse(result);
        break;
      }
      case "test": {
        const config = await getConfig();
        sendResponse({ running: await appStatus(config), port: config.port });
        break;
      }
      default:
        sendResponse({ ok: false, reason: "unknown message" });
    }
  })();
  return true;
});
