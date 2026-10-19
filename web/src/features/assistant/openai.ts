// Minimal OpenAI client (port of OpenAIClient in Assistant.swift). The key comes from this browser's
// localStorage and is only ever sent to https://api.openai.com.
const BASE = "https://api.openai.com/v1";

export const KEY_STORAGE = "assistant.openaiKey";
export const MODEL_STORAGE = "assistant.model";

/** Preferred defaults: small, fast, vision-capable models first. */
export const PREFERRED = ["gpt-5-mini", "gpt-5.1-mini", "gpt-4.1-mini", "gpt-4o-mini", "gpt-5", "gpt-4.1", "gpt-4o"];

export type ContentPart = { type: "text"; text: string } | { type: "image_url"; image_url: { url: string } };
export type ApiMessage =
  | { role: "system" | "assistant"; content: string }
  | { role: "user"; content: ContentPart[] };

export class OpenAIError extends Error {
  constructor(public kind: "noKey" | "http" | "network", message: string, public status?: number) {
    super(message);
  }
}

export const noKeyError = () => new OpenAIError("noKey", "Add your OpenAI API key in Settings to ask questions.");

function httpError(status: number, detail: string): OpenAIError {
  const message =
    status === 401 ? "OpenAI rejected the key. Check it in Settings."
    : status === 429 ? `OpenAI rate limit or quota reached. ${detail}`
    : `OpenAI error ${status}. ${detail}`;
  return new OpenAIError("http", message.trim(), status);
}

const networkError = (e: unknown) =>
  new OpenAIError("network", `Couldn't reach OpenAI (${e instanceof Error ? e.message : String(e)}). The assistant needs a connection; everything else works without one.`);

async function errorDetail(res: Response): Promise<string> {
  try {
    const body = await res.json();
    return typeof body?.error?.message === "string" ? body.error.message : "";
  } catch {
    return "";
  }
}

const isAbort = (e: unknown) => e instanceof DOMException && e.name === "AbortError";

const rank = (id: string) => {
  const i = PREFERRED.indexOf(id);
  return i < 0 ? PREFERRED.length : i;
};

/** Chat models available to this key, best defaults first. */
export async function chatModels(key: string, signal?: AbortSignal): Promise<string[]> {
  let res: Response;
  try {
    res = await fetch(`${BASE}/models`, { headers: { Authorization: `Bearer ${key}` }, signal });
  } catch (e) {
    if (isAbort(e)) throw e;
    throw networkError(e);
  }
  if (!res.ok) throw httpError(res.status, await errorDetail(res));
  const body = (await res.json()) as { data?: { id: string }[] };
  const excluded = ["audio", "realtime", "transcribe", "tts", "image", "search", "embedding", "moderation", "instruct", "codex", "computer"];
  const chat = (body.data ?? [])
    .map((m) => m.id)
    .filter((id) => (id.startsWith("gpt-") || id.startsWith("o")) && !excluded.some((x) => id.includes(x)) && !id.includes(":"));
  return chat.sort((a, b) => rank(a) - rank(b) || (a < b ? 1 : a > b ? -1 : 0));
}

const modelLists = new Map<string, Promise<string[]>>();

/** `chatModels`, fetched once per key and page load and shared by every caller (pass `fresh` to re-check). */
export function cachedChatModels(key: string, fresh = false): Promise<string[]> {
  let hit = fresh ? undefined : modelLists.get(key);
  if (!hit) {
    hit = chatModels(key);
    modelLists.set(key, hit);
    hit.catch(() => { if (modelLists.get(key) === hit) modelLists.delete(key); });
  }
  return hit;
}

/** Streams the reply text as it arrives (chat completions with server-sent events). */
export async function* streamChat(key: string, model: string, messages: ApiMessage[], signal: AbortSignal): AsyncGenerator<string> {
  let res: Response;
  try {
    res = await fetch(`${BASE}/chat/completions`, {
      method: "POST",
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ model, stream: true, messages }),
      signal,
    });
  } catch (e) {
    if (isAbort(e)) throw e;
    throw networkError(e);
  }
  if (!res.ok) throw httpError(res.status, await errorDetail(res));
  if (!res.body) throw new OpenAIError("network", "OpenAI sent an empty response.");

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  try {
    while (true) {
      let chunk: ReadableStreamReadResult<Uint8Array>;
      try {
        chunk = await reader.read();
      } catch (e) {
        if (isAbort(e)) throw e;
        throw networkError(e);
      }
      if (chunk.done) break;
      if (signal.aborted) throw new DOMException("Stopped", "AbortError");
      buffer += decoder.decode(chunk.value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() ?? "";
      for (const raw of lines) {
        const line = raw.trim();
        if (!line.startsWith("data:")) continue;
        const payload = line.slice(5).trim();
        if (payload === "[DONE]") return;
        try {
          const json = JSON.parse(payload);
          const text = json?.choices?.[0]?.delta?.content;
          if (typeof text === "string" && text) yield text;
        } catch {
          /* keep-alive or partial line: skip */
        }
      }
    }
  } finally {
    reader.cancel().catch(() => {});
  }
}
