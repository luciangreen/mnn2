const messages = document.querySelector("#messages");
const form = document.querySelector("#message-form");
const input = document.querySelector("#message-input");
const timeline = document.querySelector("#timeline");
const ruleList = document.querySelector("#rule-list");

function addMessage(text, role, response = null) {
  const item = document.createElement("article");
  item.className = `message ${role}`;
  const body = document.createElement("p");
  body.className = "answer";
  body.textContent = text;
  item.append(body);

  if (response && (response.evidence?.length || response.trace?.length)) {
    const details = document.createElement("details");
    const summary = document.createElement("summary");
    summary.textContent = "Evidence and reasoning";
    const list = document.createElement("ul");
    for (const entry of response.evidence ?? []) {
      const line = document.createElement("li");
      line.textContent = entry.source ?? JSON.stringify(entry.canonical);
      list.append(line);
    }
    for (const step of response.trace ?? []) {
      const line = document.createElement("li");
      line.textContent = step;
      list.append(line);
    }
    details.append(summary, list);
    item.append(details);
  }
  messages.append(item);
  messages.scrollTop = messages.scrollHeight;
}

async function refreshState() {
  const response = await fetch("/api/state");
  if (!response.ok) throw new Error("Unable to load conversation state");
  const state = await response.json();
  timeline.replaceChildren();
  for (const event of state.events) {
    const line = document.createElement("li");
    line.textContent = `#${event.sequence} · ${event.source}`;
    timeline.append(line);
  }
  ruleList.replaceChildren();
  if (!state.rules.length) {
    ruleList.textContent = "No rules recorded.";
  }
  for (const rule of state.rules) {
    const line = document.createElement("p");
    line.textContent = rule.text;
    ruleList.append(line);
  }
}

async function sendText(text) {
  const response = await fetch("/api/message", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text })
  });
  const result = await response.json();
  if (!response.ok) throw new Error(result.message ?? "Unable to process message");
  addMessage(result.answer, "assistant", result);
  await refreshState();
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  addMessage(text, "user");
  input.value = "";
  try {
    await sendText(text);
  } catch (error) {
    addMessage(error.message, "assistant");
  }
});

document.querySelector("#clear-button").addEventListener("click", async () => {
  await fetch("/api/reset", { method: "POST" });
  messages.replaceChildren();
  await refreshState();
});

document.querySelector("#export-button").addEventListener("click", async () => {
  const response = await fetch("/api/export");
  const data = await response.json();
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([JSON.stringify(data, null, 2)], { type: "application/json" }));
  link.download = "mnn2-knowledge.json";
  link.click();
  URL.revokeObjectURL(link.href);
});

document.querySelector("#file-input").addEventListener("change", async (event) => {
  const file = event.target.files?.[0];
  if (!file) return;
  const lines = (await file.text()).split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
  for (const line of lines) {
    addMessage(line, "user");
    try {
      await sendText(line);
    } catch (error) {
      addMessage(error.message, "assistant");
    }
  }
  event.target.value = "";
});

refreshState().catch((error) => addMessage(error.message, "assistant"));
