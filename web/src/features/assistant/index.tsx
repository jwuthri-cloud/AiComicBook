// "Ask" study companion using the reader's own OpenAI key stored in this browser (port of Assistant.swift
// and AssistantView.swift). The key lives only in localStorage ("assistant.openaiKey") and is only sent to
// https://api.openai.com.
import { createContext, useCallback, useContext, useEffect, useMemo, useReducer, useRef, useState, type ReactNode } from "react";
import { useLocation } from "react-router-dom";
import { useStore } from "../../content";
import { AssistantPanel } from "./AssistantPanel";
import { comicImage } from "./image";
import { cachedChatModels, noKeyError, PREFERRED, streamChat } from "./openai";
import { buildMessages, type ChatMessage, contextId, mentionedTerms, relatedPages, sourcesFor } from "./prompt";
import { useAssistantKey, useAssistantModel } from "./settings";
import "./assistant.css";

export { AssistantSettings } from "./settings";

export type AskContext =
  | { kind: "page"; pageId: string; showingComic?: boolean }
  | { kind: "term"; termId: string }
  | { kind: "library" };

export interface AssistantApi {
  /** Open the assistant panel about `context`, optionally sending `prompt` right away. */
  ask: (context: AskContext, prompt?: string) => void;
}

const Ctx = createContext<AssistantApi>({ ask: () => {} });
export const useAssistant = () => useContext(Ctx);

interface Session {
  /** Unique per conversation, so late stream chunks from a replaced chat are dropped. */
  token: number;
  context: AskContext;
  id: string;
  messages: ChatMessage[];
  streaming: boolean;
}

let counter = 0;
const nextId = () => ++counter;
const isAbort = (e: unknown) => e instanceof DOMException && e.name === "AbortError";

export function AssistantProvider({ children }: { children: ReactNode }) {
  const store = useStore();
  const location = useLocation();
  const [apiKey] = useAssistantKey();
  const [model, setModel] = useAssistantModel();
  const [open, setOpen] = useState(false);
  const [, rerender] = useReducer((x: number) => x + 1, 0);

  // The conversation lives in a ref so the streaming loop always patches the latest version.
  const session = useRef<Session | null>(null);
  const abort = useRef<AbortController>();
  const pending = useRef<string>();
  const keyRef = useRef(apiKey);
  const modelRef = useRef(model);
  keyRef.current = apiKey;
  modelRef.current = model;

  const update = useCallback((token: number, fn: (s: Session) => Session) => {
    const s = session.current;
    if (!s || s.token !== token) return;
    session.current = fn(s);
    rerender();
  }, []);

  const send = useCallback(async (raw: string, image?: string, canned = false) => {
    const s = session.current;
    if (!s || s.streaming) return;
    const token = s.token;
    const key = keyRef.current;
    if (!key) {
      update(token, (x) => ({ ...x, messages: [...x.messages, { id: nextId(), role: "assistant", text: noKeyError().message, sources: [], failed: true }] }));
      return;
    }
    const question = raw.trim();
    if (!question && !image) return;

    const related = relatedPages(store, question, s.context, canned);
    const terms = mentionedTerms(store, question, s.context);
    const user: ChatMessage = { id: nextId(), role: "user", text: question, image, sources: [] };
    const replyId = nextId();
    const history = [...s.messages, user];
    session.current = {
      ...s,
      messages: [...history, { id: replyId, role: "assistant", text: "", sources: sourcesFor(s.context, related, terms) }],
      streaming: true,
    };
    rerender();

    const controller = new AbortController();
    abort.current = controller;
    const patchReply = (fn: (m: ChatMessage) => ChatMessage) =>
      update(token, (x) => ({ ...x, messages: x.messages.map((m) => (m.id === replyId ? fn(m) : m)) }));
    let received = false;
    try {
      let chosen = modelRef.current;
      if (!chosen) {
        chosen = await cachedChatModels(key).then((list) => list[0] ?? PREFERRED[0], () => PREFERRED[0]);
        if (controller.signal.aborted) throw new DOMException("Stopped", "AbortError");
        setModel(chosen);
      }
      const c = s.context;
      const page = c.kind === "page" && c.showingComic ? store.pages.get(c.pageId) : undefined;
      const comic = page ? await comicImage(page.image) : undefined;
      const payload = buildMessages(store, c, history, related, terms, comic);
      for await (const chunk of streamChat(key, chosen, payload, controller.signal)) {
        received = true;
        patchReply((m) => ({ ...m, text: m.text + chunk }));
      }
      if (!received) patchReply((m) => ({ ...m, text: "OpenAI sent an empty answer. Try again, or pick another model in Settings.", failed: true }));
    } catch (e) {
      if (!isAbort(e)) patchReply((m) => ({ ...m, text: e instanceof Error ? e.message : String(e), failed: true }));
    } finally {
      if (abort.current === controller) abort.current = undefined;
      // A reply stopped before its first word is dropped.
      update(token, (x) => ({ ...x, streaming: false, messages: x.messages.filter((m) => m.id !== replyId || m.text) }));
    }
  }, [store, update, setModel]);

  const stop = useCallback(() => abort.current?.abort(), []);

  const reset = useCallback(() => {
    abort.current?.abort();
    const s = session.current;
    if (s) session.current = { token: nextId(), context: s.context, id: s.id, messages: [], streaming: false };
    rerender();
  }, []);

  const ask = useCallback((context: AskContext, prompt?: string) => {
    const id = contextId(context);
    // Same page or word as last time: continue that conversation.
    if (session.current?.id !== id) {
      abort.current?.abort();
      session.current = { token: nextId(), context, id, messages: [], streaming: false };
    }
    setOpen(true);
    rerender();
    if (prompt) {
      if (keyRef.current) void send(prompt, undefined, true);
      else pending.current = prompt;
    }
  }, [send]);

  const close = useCallback(() => setOpen(false), []);

  // A prompt asked before the key was added is sent once the key is saved.
  useEffect(() => {
    if (open && apiKey && pending.current) {
      const prompt = pending.current;
      pending.current = undefined;
      void send(prompt, undefined, true);
    }
  }, [open, apiKey, send]);

  // Following a link elsewhere closes the panel.
  useEffect(() => { setOpen(false); }, [location.pathname]);

  useEffect(() => () => abort.current?.abort(), []);

  const api = useMemo<AssistantApi>(() => ({ ask }), [ask]);
  const s = session.current;

  return (
    <Ctx.Provider value={api}>
      {children}
      {open && s && (
        <AssistantPanel
          context={s.context}
          messages={s.messages}
          streaming={s.streaming}
          hasKey={!!apiKey}
          model={model}
          onClose={close}
          onSend={send}
          onStop={stop}
          onReset={reset}
        />
      )}
    </Ctx.Provider>
  );
}
