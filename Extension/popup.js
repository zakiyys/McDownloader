const statusDot = document.getElementById("status-dot");
const statusText = document.getElementById("status-text");
const urlField = document.getElementById("url");
const message = document.getElementById("message");

async function refreshStatus() {
  const response = await chrome.runtime.sendMessage({ type: "status" });
  if (response && response.running) {
    statusDot.classList.add("ok");
    statusText.textContent = `Connected on port ${response.port}`;
  } else {
    statusDot.classList.remove("ok");
    statusText.textContent = "App not running";
    message.textContent = "Open McDownloader to start receiving downloads.";
  }
}

async function preloadCurrentTab() {
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (tab && tab.url && !tab.url.startsWith("chrome://")) {
    urlField.value = tab.url;
  }
}

document.getElementById("add").addEventListener("click", async () => {
  const url = urlField.value.trim();
  if (!url) {
    message.textContent = "Paste a link first.";
    return;
  }
  message.textContent = "Sending…";
  const result = await chrome.runtime.sendMessage({ type: "add", url, referer: "" });
  if (result && result.ok) {
    message.textContent = "Added to the queue.";
    urlField.value = "";
  } else {
    message.textContent =
      result && result.reason === "app-not-running"
        ? "McDownloader is not running."
        : `Could not add the link: ${result ? result.reason : "unknown error"}`;
  }
});

document.getElementById("grab").addEventListener("click", async (event) => {
  event.preventDefault();
  // The media grabber lives in the app; the extension just points it at the page.
  const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  if (!tab || !tab.url) return;
  const result = await chrome.runtime.sendMessage({ type: "add", url: tab.url, referer: "" });
  message.textContent = result && result.ok
    ? "Page sent to the app. Use Grab media there for video."
    : "Could not reach the app.";
});

document.getElementById("options").addEventListener("click", (event) => {
  event.preventDefault();
  chrome.runtime.openOptionsPage();
});

refreshStatus();
preloadCurrentTab();
