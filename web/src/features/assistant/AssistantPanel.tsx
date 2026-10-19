// The slide-over chat (port of AssistantView.swift): bottom sheet on phones, right drawer on desktop.
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type KeyboardEvent, type ReactNode } from "react";
import { Link } from "react-router-dom";
import { type Store, url, useStore } from "../../content";
import { Icon, categoryTint, tinted } from "../../ui";
import type { AskContext } from ".";
import { jpegDataURL } from "./image";
import { Markdown } from "./markdown";
import { type ChatMessage, type Source, suggestions } from "./prompt";
import { AssistantSettings } from "./settings";

export interface PanelProps {
  context: AskContext;
  messages: ChatMessage[];
  streaming: boolean;
  hasKey: boolean;
  model: string;
  onClose: () => void;
  onSend: (text: string, image?: string, canned?: boolean) => void;
  onStop: () => void;
  onReset: () => void;
}

export function AssistantPanel(props: PanelProps) {
  const { context, messages, streaming, hasKey, model, onClose, onSend, onStop, onReset } = props;
  const [draft, setDraft] = useState("");
  const [attachment, setAttachment] = useState<string>();
  const [attachError, setAttachError] = useState<string>();
  const scrollRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLTextAreaElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  // Escape closes; the page behind stays put.
  useEffect(() => {
    const onKey = (e: globalThis.KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", onKey);
    const root = document.documentElement;
    const previous = root.style.overflow;
    root.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      root.style.overflow = previous;
    };
  }, [onClose]);

  // Follow the reply as it streams in.
  const last = messages[messages.length - 1];
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages.length, last?.text]);

  // Keyboard focus on desktop only (on phones it would pop the keyboard over the context card).
  useEffect(() => {
    if (hasKey && window.matchMedia("(min-width: 721px)").matches) inputRef.current?.focus();
  }, [hasKey]);

  // Grow the text box up to five lines.
  useEffect(() => {
    const el = inputRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 132)}px`;
  }, [draft]);

  const canSend = !!draft.trim() || !!attachment;

  function send(text: string, canned = false) {
    if (streaming) return;
    if (!text.trim() && !attachment) return;
    onSend(text, attachment, canned);
    setDraft("");
    setAttachment(undefined);
  }

  function submit(e?: FormEvent) {
    e?.preventDefault();
    if (streaming) onStop();
    else send(draft);
  }

  function onKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing) {
      e.preventDefault();
      if (!streaming) send(draft);
    }
  }

  async function onPick(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setAttachError(undefined);
    try {
      setAttachment(await jpegDataURL(file));
    } catch {
      setAttachError("That image couldn't be read. Try a JPEG or PNG.");
    }
  }

  return (
    <div className="ask-overlay" onClick={onClose}>
      <aside className="ask-panel" role="dialog" aria-modal="true" aria-label="Ask the study companion" onClick={(e) => e.stopPropagation()}>
        <header className="ask-head">
          <span className="ask-head-icon"><Icon name="sparkles" /></span>
          <div className="stack" style={{ ["--gap" as string]: "0px", flex: 1, minWidth: 0 }}>
            <strong className="serif" style={{ fontSize: 18 }}>Ask</strong>
            {hasKey && <span className="tiny faint">{model || "Model picked on first question"}</span>}
          </div>
          {hasKey && messages.length > 0 && (
            <button className="ask-icon" aria-label="New chat" title="New chat" onClick={onReset}><Icon name="refresh" /></button>
          )}
          <button className="ask-icon" aria-label="Close" onClick={onClose}><Icon name="close" /></button>
        </header>

        {hasKey ? (
          <>
            <div className="ask-body" ref={scrollRef}>
              <ContextCard context={context} />
              {messages.length === 0 && (
                <div className="stack" style={{ ["--gap" as string]: "8px" }}>
                  {suggestions(context).map((s) => (
                    <button key={s} className="ask-suggestion" onClick={() => send(s, true)}>
                      <span>{s}</span>
                      <Icon name="right" size={16} />
                    </button>
                  ))}
                </div>
              )}
              {messages.map((m) => (
                <Message key={m.id} message={m} streaming={streaming && m.id === last?.id} onOpen={onClose} />
              ))}
            </div>

            <form className="ask-input" onSubmit={submit}>
              {attachment && (
                <div className="ask-attachment">
                  <img src={attachment} alt="Attached photo" />
                  <button type="button" aria-label="Remove photo" onClick={() => setAttachment(undefined)}><Icon name="close" size={14} /></button>
                </div>
              )}
              {attachError && <p className="tiny" style={{ color: "var(--coral)" }}>{attachError}</p>}
              <div className="ask-input-row">
                <button type="button" className="ask-icon" aria-label="Attach a photo" title="Attach a photo" onClick={() => fileRef.current?.click()}>
                  <Icon name="image" />
                </button>
                <input ref={fileRef} type="file" accept="image/*" hidden onChange={onPick} />
                <textarea
                  ref={inputRef}
                  className="ask-textarea"
                  rows={1}
                  placeholder="Ask anything…"
                  value={draft}
                  onChange={(e) => setDraft(e.target.value)}
                  onKeyDown={onKeyDown}
                  aria-label="Your question"
                />
                <button type="submit" className="ask-send" disabled={!streaming && !canSend} aria-label={streaming ? "Stop" : "Send"}>
                  {streaming ? <span className="ask-stop-square" /> : <ArrowUp />}
                </button>
              </div>
            </form>
          </>
        ) : (
          <div className="ask-body">
            <div className="stack" style={{ ["--gap" as string]: "10px" }}>
              <h2 className="title-m">Connect your OpenAI key</h2>
              <p className="serif muted">
                The assistant uses your own OpenAI account. Paste an API key below or in{" "}
                <Link to="/settings" className="assistant-link" onClick={onClose}>Settings</Link>. It is stored only in this browser and sent only to OpenAI;
                the questions, page text and images you ask about go to OpenAI too. Everything else stays on this device.
              </p>
            </div>
            <AssistantSettings />
            <Link to="/settings" className="btn secondary" onClick={onClose}><Icon name="settings" />Open Settings</Link>
          </div>
        )}
      </aside>
    </div>
  );
}

function ContextCard({ context }: { context: AskContext }) {
  const store = useStore();
  let icon: ReactNode, title: string, subtitle: string;
  if (context.kind === "page") {
    const page = store.pages.get(context.pageId);
    icon = page ? <img className="ask-context-thumb" src={url(page.thumb)} alt="" /> : <Icon name="text" />;
    title = page?.title ?? "This page";
    subtitle = context.showingComic ? "Knows this page (text and comic image) and the whole library" : "Knows this page and the whole library";
  } else if (context.kind === "term") {
    const term = store.terms.get(context.termId);
    icon = <span className="ask-context-icon" style={tinted(categoryTint(term?.category ?? ""))}><Icon name="glossary" /></span>;
    title = term?.term ?? "This word";
    subtitle = "Knows this word and the whole library";
  } else {
    icon = <span className="ask-context-icon"><Icon name="sparkles" /></span>;
    title = "Your study companion";
    subtitle = `Ask about anything in the ${store.pages.size} pages, or send a photo`;
  }
  return (
    <div className="card ask-context">
      {icon}
      <div className="stack" style={{ ["--gap" as string]: "2px", minWidth: 0 }}>
        <strong className="serif ask-context-title">{title}</strong>
        <span className="tiny muted">{subtitle}</span>
      </div>
    </div>
  );
}

interface SourceLink { to: string; title: string; icon: string }

function sourceLink(store: Store, s: Source): SourceLink | undefined {
  if (s.kind === "term") {
    const term = store.terms.get(s.id);
    return term && { to: `/glossary/${term.id}`, title: term.term, icon: "glossary" };
  }
  const page = store.pages.get(s.id);
  const book = page && store.bookFor(page);
  if (!page || !book) return undefined;
  return { to: `/read/${book.id}/${book.pages.findIndex((p) => p.id === page.id)}`, title: page.title, icon: "books" };
}

function Message({ message, streaming, onOpen }: { message: ChatMessage; streaming: boolean; onOpen: () => void }) {
  const store = useStore();
  if (message.role === "user") {
    return (
      <div className="ask-user">
        {message.image && <img src={message.image} alt="Attached photo" />}
        {message.text && <div className="ask-user-text serif">{message.text}</div>}
      </div>
    );
  }
  const links = !streaming && !message.failed ? message.sources.map((s) => sourceLink(store, s)).filter((l): l is SourceLink => !!l) : [];
  return (
    <div className={`card ask-reply${message.failed ? " failed" : ""}`}>
      {!message.text && streaming ? (
        <span className="ask-dots" aria-label="Thinking"><i /><i /><i /></span>
      ) : message.failed ? (
        <p className="serif">
          {message.text}
          {/Settings/.test(message.text) && <> <Link to="/settings" className="assistant-link" onClick={onOpen}>Open Settings</Link></>}
        </p>
      ) : (
        <Markdown text={message.text} />
      )}
      {links.length > 0 && (
        <div className="ask-sources">
          {links.map((l) => (
            <Link key={l.to} to={l.to} className="ask-source" onClick={onOpen}>
              <Icon name={l.icon} size={14} />
              <span>{l.title}</span>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}

const ArrowUp = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2.6} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    <path d="M12 19V5M5 12l7-7 7 7" />
  </svg>
);
