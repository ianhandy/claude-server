import express from "express";
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const app = express();
const PORT = process.env.PORT || 3000;
const TASKS_DIR = process.env.TASKS_DIR || path.join(__dirname, "../tasks");

// OpenRouter config — uses free models by default (no cost).
// Set OPENROUTER_API_KEY in your environment or .env file.
const OPENROUTER_KEY = process.env.OPENROUTER_API_KEY || "";
const OPENROUTER_MODEL = process.env.OPENROUTER_MODEL || "openrouter/free";
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

app.use(express.json());
app.use(express.static(path.join(__dirname, "public")));

// ── /api/status — heartbeat + active task ─────────────────────────────────────
app.get("/api/status", (req, res) => {
  let heartbeat = null;
  const hbPath = path.join(TASKS_DIR, "heartbeat.json");
  if (fs.existsSync(hbPath)) {
    try { heartbeat = JSON.parse(fs.readFileSync(hbPath, "utf8")); } catch {}
  }

  const lockPath = path.join(TASKS_DIR, "ACTIVE_TASK");
  const activeTask = fs.existsSync(lockPath)
    ? fs.readFileSync(lockPath, "utf8").trim()
    : null;

  const blockerPath = path.join(TASKS_DIR, "BLOCKER.md");
  const hasBlocker = fs.existsSync(blockerPath);
  const hasResponse = fs.existsSync(path.join(TASKS_DIR, "BLOCKER_RESPONSE.md"));

  const briefsDir = path.join(TASKS_DIR, "briefs");
  let lastBrief = null;
  if (fs.existsSync(briefsDir)) {
    const dates = fs.readdirSync(briefsDir).filter(f => f.endsWith(".md")).sort();
    if (dates.length) lastBrief = dates[dates.length - 1].replace(".md", "");
  }

  res.json({ heartbeat, activeTask, hasBlocker, hasResponse, lastBrief });
});

// ── /api/blocker — return BLOCKER.md ──────────────────────────────────────────
app.get("/api/blocker", (req, res) => {
  const blockerPath = path.join(TASKS_DIR, "BLOCKER.md");
  if (!fs.existsSync(blockerPath)) return res.json({ content: null });
  res.json({ content: fs.readFileSync(blockerPath, "utf8") });
});

// ── /api/blocker-response — write operator's decision ─────────────────────────
app.post("/api/blocker-response", (req, res) => {
  const { decision, conversation } = req.body;
  if (!decision) return res.status(400).json({ error: "No decision provided" });

  const response = [
    "# Blocker Response",
    `**Recorded:** ${new Date().toISOString()}`,
    "",
    "## Decision",
    decision,
    "",
    "## Full Conversation",
    conversation || "(none)",
  ].join("\n");

  fs.writeFileSync(path.join(TASKS_DIR, "BLOCKER_RESPONSE.md"), response);
  res.json({ ok: true });
});

// ── /api/briefs — list archived brief dates ───────────────────────────────────
app.get("/api/briefs", (req, res) => {
  const briefsDir = path.join(TASKS_DIR, "briefs");
  if (!fs.existsSync(briefsDir)) return res.json({ dates: [] });
  const dates = fs.readdirSync(briefsDir)
    .filter(f => f.endsWith(".md"))
    .map(f => f.replace(".md", ""))
    .sort().reverse();
  res.json({ dates });
});

// ── /api/brief/:date — return a specific brief ────────────────────────────────
app.get("/api/brief/:date?", (req, res) => {
  const filePath = req.params.date
    ? path.join(TASKS_DIR, "briefs", `${req.params.date}.md`)
    : path.join(TASKS_DIR, "BRIEF.md");
  if (!fs.existsSync(filePath)) return res.json({ content: "*No brief for this date.*" });
  res.json({ content: fs.readFileSync(filePath, "utf8") });
});

// ── Build context ─────────────────────────────────────────────────────────────
function buildContext() {
  const parts = [];

  const briefPath = path.join(TASKS_DIR, "BRIEF.md");
  if (fs.existsSync(briefPath))
    parts.push("## Daily Brief\n" + fs.readFileSync(briefPath, "utf8"));

  return parts.join("\n\n---\n\n");
}

// ── /api/chat — streaming chat via OpenRouter ────────────────────────────────
app.post("/api/chat", async (req, res) => {
  const { messages, mode } = req.body;
  if (!messages?.length) return res.status(400).json({ error: "No messages" });

  if (!OPENROUTER_KEY) {
    return res.status(500).json({ error: "OPENROUTER_API_KEY not configured. Set it in your environment." });
  }

  res.setHeader("Content-Type", "text/event-stream");
  res.setHeader("Cache-Control", "no-cache");
  res.setHeader("Connection", "keep-alive");

  const context = buildContext();

  let systemPreamble = "";
  if (mode === "blocker") {
    const blockerPath = path.join(TASKS_DIR, "BLOCKER.md");
    const blockerContent = fs.existsSync(blockerPath)
      ? fs.readFileSync(blockerPath, "utf8")
      : "(BLOCKER.md not found)";
    systemPreamble = `\n\n## ACTIVE BLOCKER\nThis conversation exists to resolve a blocker. Present the situation clearly, ask the minimum necessary to make a call, and confirm the decision explicitly before submission.\n\n${blockerContent}`;
  }

  const persona = mode === "blocker"
    ? "You are a decision assistant. A blocker has stopped autonomous work. Help the operator understand the situation and make a clear call. Be direct."
    : "You are a briefing assistant. Answer questions about recent work, decisions, and what's coming. Be concise.";

  const systemMsg = `${persona}\n\n## Server Context\n${context}${systemPreamble}`;

  const orMessages = [
    { role: "system", content: systemMsg },
    ...messages.map(m => ({ role: m.role, content: m.content })),
  ];

  try {
    const orRes = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENROUTER_KEY}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "http://localhost:3000",
        "X-OpenRouter-Title": "Claude Server Dashboard",
      },
      body: JSON.stringify({
        model: OPENROUTER_MODEL,
        messages: orMessages,
        stream: true,
      }),
    });

    if (!orRes.ok) {
      const errText = await orRes.text();
      console.error(`[chat] OpenRouter error ${orRes.status}: ${errText}`);
      res.write(`data: ${JSON.stringify({ error: `OpenRouter ${orRes.status}: ${errText}` })}\n\n`);
      res.write("data: [DONE]\n\n");
      res.end();
      return;
    }

    const reader = orRes.body.getReader();
    const decoder = new TextDecoder();
    let buf = "";

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buf += decoder.decode(value, { stream: true });
      const lines = buf.split("\n");
      buf = lines.pop();

      for (const line of lines) {
        if (!line.startsWith("data: ")) continue;
        const raw = line.slice(6).trim();
        if (raw === "[DONE]") continue;

        try {
          const chunk = JSON.parse(raw);
          const delta = chunk.choices?.[0]?.delta?.content;
          if (delta) {
            res.write(`data: ${JSON.stringify({ text: delta })}\n\n`);
          }
        } catch {}
      }
    }

    res.write("data: [DONE]\n\n");
    res.end();
  } catch (err) {
    console.error("[chat] fetch error:", err.message);
    res.write(`data: ${JSON.stringify({ error: err.message })}\n\n`);
    res.write("data: [DONE]\n\n");
    res.end();
  }
});

// ── /api/inbox — drop a message for the autonomous Claude instance ───────────
app.post("/api/inbox", (req, res) => {
  const { message } = req.body;
  if (!message?.trim()) return res.status(400).json({ error: "No message" });

  const inboxDir = path.join(TASKS_DIR, "inbox");
  if (!fs.existsSync(inboxDir)) fs.mkdirSync(inboxDir, { recursive: true });

  const now = new Date();
  const stamp = now.toISOString().replace(/[-:T]/g, "").slice(0, 12);
  const filename = `msg-${stamp}.md`;
  fs.writeFileSync(path.join(inboxDir, filename), message.trim() + "\n");

  res.json({ ok: true, file: filename });
});

// ── /api/chat-log — persist chat transcript ──────────────────────────────────
app.post("/api/chat-log", (req, res) => {
  const { messages } = req.body;
  if (!messages?.length) return res.status(400).json({ error: "No messages" });

  const logDir = path.join(TASKS_DIR, "chats");
  if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });

  const today = new Date().toISOString().slice(0, 10);
  const logPath = path.join(logDir, `${today}.md`);

  const transcript = messages
    .map(m => `**${m.role === "user" ? "You" : "Assistant"}:** ${m.content}`)
    .join("\n\n");

  const entry = `\n---\n\n_${new Date().toISOString()}_\n\n${transcript}\n`;
  fs.appendFileSync(logPath, entry);

  res.json({ ok: true });
});

app.listen(PORT, () => console.log(`Dashboard at http://localhost:${PORT}`));
