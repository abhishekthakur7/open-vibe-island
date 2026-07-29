// Open Island plugin for OpenCode
// Bridges OpenCode events to the Open Island desktop app via Unix socket.
// Install: copy to ~/.config/opencode/plugins/open-island.js
import { appendFileSync, existsSync } from "fs";
import { homedir } from "os";
import { spawnSync } from "child_process";

// Debug logging is OFF by default. When enabled via OPEN_ISLAND_DEBUG, it writes to the
// user-owned app-support directory (not world-readable /tmp), because it can contain
// prompt text, tool inputs, and bash command patterns.
const DEBUG_ENABLED = !!process.env.OPEN_ISLAND_DEBUG;
const DEBUG_LOG = `${process.env.HOME || homedir()}/Library/Application Support/OpenIsland/opencode-debug.log`;
function debugLog(msg) {
  if (!DEBUG_ENABLED) return;
  try { appendFileSync(DEBUG_LOG, `[${new Date().toISOString()}] ${msg}\n`); } catch {}
}

// OpenCode never speaks the bridge protocol directly. The fixed bundled helper
// owns the signed hook-event-submit role and the Keychain bootstrap material.
const BUNDLED_HOOK_HELPER = "/Applications/Open Island.app/Contents/Helpers/OpenIslandHooks";

function sendToSocket(json) {
  try {
    if (!existsSync(BUNDLED_HOOK_HELPER)) return Promise.resolve(false);
    const result = spawnSync(BUNDLED_HOOK_HELPER, ["--source", "opencode"], {
      input: JSON.stringify(json.openCodeHook), encoding: "utf8", timeout: 3000,
      killSignal: "SIGKILL", cwd: "/", env: {},
      stdio: ["pipe", "ignore", "ignore"],
    });
    return Promise.resolve(!result.error && result.status === 0);
  } catch { return Promise.resolve(false); }
}

const ENV_KEYS = [
  "TERM_PROGRAM", "ITERM_SESSION_ID", "TERM_SESSION_ID",
  "TMUX", "TMUX_PANE", "KITTY_WINDOW_ID",
  "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_SOCKET_PATH",
  "ZELLIJ", "ZELLIJ_PANE_ID", "ZELLIJ_SESSION_NAME",
];

function collectEnv() {
  const env = {};
  for (const k of ENV_KEYS) { if (process.env[k]) env[k] = process.env[k]; }
  return env;
}

function terminalFields() {
  const env = process.env;
  const result = {};
  if (env.ITERM_SESSION_ID) {
    result.terminal_app = "iTerm";
    result.terminal_session_id = env.ITERM_SESSION_ID;
  } else if (env.CMUX_WORKSPACE_ID || env.CMUX_SOCKET_PATH) {
    result.terminal_app = "cmux";
    if (env.CMUX_SURFACE_ID) result.terminal_session_id = env.CMUX_SURFACE_ID;
  } else if (env.ZELLIJ != null) {
    result.terminal_app = "Zellij";
    const paneID = env.ZELLIJ_PANE_ID || "";
    const sessionName = env.ZELLIJ_SESSION_NAME || "";
    if (paneID) result.terminal_session_id = `${paneID}:${sessionName}`;
  } else if (env.GHOSTTY_RESOURCES_DIR || (env.TERM_PROGRAM || "").toLowerCase().includes("ghostty")) {
    result.terminal_app = "Ghostty";
  } else if (env.TERM_PROGRAM === "Apple_Terminal") {
    result.terminal_app = "Terminal";
  } else if (env.TERM_PROGRAM) {
    result.terminal_app = env.TERM_PROGRAM;
  }
  return result;
}

function makePayload(hookEventName, sessionID, cwd, extra = {}) {
  return {
    type: "processOpenCodeHook",
    openCodeHook: {
      hook_event_name: hookEventName,
      session_id: `opencode-${sessionID}`,
      cwd: cwd || ".",
      ...terminalFields(),
      ...extra,
    },
  };
}

function normalizeQuestionOption(option) {
  if (typeof option === "string") {
    return { label: option };
  }
  if (!option || typeof option !== "object") {
    return null;
  }

  const label = option.label || option.text || option.value || option.name;
  if (!label) return null;

  return {
    label: String(label),
    description: option.description || option.hint || option.detail || "",
    allows_freeform: Boolean(option.allowsFreeform || option.allows_freeform),
  };
}

function normalizeQuestion(question, index) {
  if (!question || typeof question !== "object") {
    return null;
  }

  const questionText = question.question || question.title || question.prompt;
  if (!questionText) return null;

  const options = Array.isArray(question.options)
    ? question.options.map(normalizeQuestionOption).filter(Boolean)
    : [];
  if (options.length === 0) return null;

  return {
    question: String(questionText),
    header: question.header || question.label || `Question ${index + 1}`,
    options,
    multi_select: Boolean(question.multiSelect || question.multi_select),
  };
}

export default async () => {
  const msgRoles = new Map();
  const sessionCwd = new Map();
  const sessions = new Map();

  function getSession(sid) {
    if (!sessions.has(sid)) sessions.set(sid, { lastAssistantText: "" });
    return sessions.get(sid);
  }

  function mapEvent(ev) {
    const t = ev.type;
    const p = ev.properties || {};

    // session.created
    if (t === "session.created" && p.info) {
      const cwd = p.info.directory || "";
      sessionCwd.set(p.info.id, cwd);
      return makePayload("SessionStart", p.info.id, cwd);
    }

    // session.deleted
    if (t === "session.deleted" && p.info) {
      sessions.delete(p.info.id);
      sessionCwd.delete(p.info.id);
      return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
    }

    // session.updated (archived)
    if (t === "session.updated" && p.info) {
      if (p.info.directory) sessionCwd.set(p.info.id, p.info.directory);
      if (p.info.time?.archived) {
        sessions.delete(p.info.id);
        sessionCwd.delete(p.info.id);
        return makePayload("SessionEnd", p.info.id, sessionCwd.get(p.info.id));
      }
      return null;
    }

    // session.status → idle = Stop (busy is ignored; session creation
    // comes from session.created or ensureOpenCodeSessionExists on first event)
    if (t === "session.status" && p.sessionID) {
      if (p.status?.type === "idle") {
        const s = getSession(p.sessionID);
        return makePayload("Stop", p.sessionID, sessionCwd.get(p.sessionID), {
          last_assistant_message: s.lastAssistantText || undefined,
        });
      }
      return null;
    }

    // message.updated — track role for message parts
    if (t === "message.updated" && p.info?.id && p.info?.sessionID) {
      msgRoles.set(p.info.id, { role: p.info.role, sessionID: p.info.sessionID });
      if (msgRoles.size > 200) { msgRoles.delete(msgRoles.keys().next().value); }
      return null;
    }

    // message.part.updated — text
    if (t === "message.part.updated" && p.part?.type === "text" && p.part?.messageID) {
      const meta = msgRoles.get(p.part.messageID);
      if (!meta) return null;
      const text = p.part.text || "";
      if (meta.role === "user" && text) {
        return makePayload("UserPromptSubmit", meta.sessionID, sessionCwd.get(meta.sessionID), {
          prompt: text,
        });
      }
      if (meta.role === "assistant" && text) {
        getSession(meta.sessionID).lastAssistantText = text;
      }
      return null;
    }

    // message.part.updated — tool
    if (t === "message.part.updated" && p.part?.type === "tool" && p.part?.sessionID) {
      const st = p.part.state?.status;
      const cwd = sessionCwd.get(p.part.sessionID);
      const toolName = (p.part.tool || "").charAt(0).toUpperCase() + (p.part.tool || "").slice(1);
      if (st === "running" || st === "pending") {
        return makePayload("PreToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
          tool_input: typeof p.part.state?.input === "string"
            ? p.part.state.input
            : JSON.stringify(p.part.state?.input || {}).slice(0, 200),
        });
      }
      if (st === "completed" || st === "error") {
        return makePayload("PostToolUse", p.part.sessionID, cwd, {
          tool_name: toolName,
        });
      }
      return null;
    }

    // permission.asked
    if (t === "permission.asked" && p.id && p.sessionID) {
      const toolName = (p.permission || "").charAt(0).toUpperCase() + (p.permission || "").slice(1);
      const patterns = p.patterns || [];
      const toolInput = { patterns, metadata: p.metadata };
      if (p.permission === "bash" && patterns.length > 0) {
        toolInput.command = patterns.join(" && ");
      }
      if ((p.permission === "edit" || p.permission === "write") && patterns.length > 0) {
        toolInput.file_path = patterns[0];
      }
      return makePayload("PermissionRequest", p.sessionID, sessionCwd.get(p.sessionID), {
        tool_name: toolName,
        tool_input: JSON.stringify(toolInput).slice(0, 200),
        permission_id: p.id,
        permission_title: `Allow ${toolName}`,
        permission_description: patterns.length > 0
          ? `OpenCode wants to run ${toolName}: ${patterns[0]}`
          : `OpenCode wants to run ${toolName}`,
        _opencode_request_id: p.id,
      });
    }

    // permission.replied
    if (t === "permission.replied" && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    // question.asked
    if (t === "question.asked" && p.id && p.sessionID) {
      const questions = Array.isArray(p.questions)
        ? p.questions.map(normalizeQuestion).filter(Boolean)
        : [];
      return makePayload("QuestionAsked", p.sessionID, sessionCwd.get(p.sessionID), {
        question_id: p.id,
        question_text: (p.questions || []).map(q => q.question).join("; ") || "OpenCode has a question",
        questions,
        _opencode_request_id: p.id,
      });
    }

    // question.replied / question.rejected
    if ((t === "question.replied" || t === "question.rejected") && p.sessionID) {
      return makePayload("PostToolUse", p.sessionID, sessionCwd.get(p.sessionID));
    }

    return null;
  }

  return {
    "event": async ({ event }) => {
      try {
        debugLog(`EVENT: ${event.type} | props: ${JSON.stringify(event.properties || {}).slice(0, 300)}`);
        const mapped = mapEvent(event);
        if (mapped) {
          debugLog(`MAPPED: ${mapped.openCodeHook.hook_event_name} sid=${mapped.openCodeHook.session_id}`);
        }
        if (!mapped) return;

        // Every event uses the local Unix bridge. The former loopback reply
        // path would create an IP request from this bundled resource.
        await sendToSocket(mapped);
      } catch {
        // Fail open: if Open Island is unavailable, don't block OpenCode
      }
    },

    "shell.env": async (input, output) => {
      output.env.OPEN_ISLAND_ACTIVE = "1";
      for (const v of ENV_KEYS) {
        if (process.env[v]) output.env["_OI_" + v] = process.env[v];
      }
    },
  };
};
