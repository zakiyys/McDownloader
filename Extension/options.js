const DEFAULTS = { port: 6847, token: "", intercept: true, enabled: true };

const fields = {
  port: document.getElementById("port"),
  token: document.getElementById("token"),
  intercept: document.getElementById("intercept"),
  enabled: document.getElementById("enabled")
};
const status = document.getElementById("status");

async function load() {
  const config = { ...DEFAULTS, ...(await chrome.storage.local.get(DEFAULTS)) };
  fields.port.value = config.port;
  fields.token.value = config.token;
  fields.intercept.checked = config.intercept;
  fields.enabled.checked = config.enabled;
}

document.getElementById("settings").addEventListener("submit", async (event) => {
  event.preventDefault();
  await chrome.storage.local.set({
    port: Number(fields.port.value) || DEFAULTS.port,
    token: fields.token.value.trim(),
    intercept: fields.intercept.checked,
    enabled: fields.enabled.checked
  });
  status.textContent = "Saved.";
});

document.getElementById("test").addEventListener("click", async () => {
  status.textContent = "Testing…";
  const response = await chrome.runtime.sendMessage({ type: "test" });
  status.textContent = response && response.running
    ? `Connected on port ${response.port}.`
    : "No response. Is the app running and is the token correct?";
});

load();
