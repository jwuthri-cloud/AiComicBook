// Settings card for the assistant: paste / clear the OpenAI key (this browser's localStorage only) and pick
// a model (port of KeySetupCard + AssistantSettingsSection).
import { useEffect, useRef, useState, type FormEvent } from "react";
import { useLocal } from "../../store";
import { Icon } from "../../ui";
import { cachedChatModels, KEY_STORAGE, MODEL_STORAGE, OpenAIError, PREFERRED } from "./openai";

export function useAssistantKey() {
  return useLocal<string>(KEY_STORAGE, "");
}

export function useAssistantModel() {
  return useLocal<string>(MODEL_STORAGE, "");
}

const describe = (e: unknown) => (e instanceof Error ? e.message : String(e));

export function AssistantSettings() {
  const [key, setKey] = useAssistantKey();
  const [model, setModel] = useAssistantModel();
  const [draft, setDraft] = useState("");
  const [status, setStatus] = useState<string>();
  const [checking, setChecking] = useState(false);
  const [models, setModels] = useState<string[]>([]);
  const saving = useRef(false);

  // Load the models this key can use (one request per key and page load, shared with the chat).
  useEffect(() => {
    if (!key) { setModels([]); return; }
    let live = true;
    cachedChatModels(key).then(
      (list) => {
        if (!live) return;
        setModels(list);
        if (list.length && (!model || !list.includes(model))) setModel(list[0]);
      },
      (e) => { if (live && !saving.current) setStatus(describe(e)); },
    );
    return () => { live = false; };
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps

  async function save(e: FormEvent) {
    e.preventDefault();
    const trimmed = draft.trim();
    if (!trimmed || checking) return;
    // Keep the key even if the check below fails (offline, flaky network…); only a rejected key is removed.
    const check = cachedChatModels(trimmed, true);
    saving.current = true;
    setKey(trimmed);
    setDraft("");
    setChecking(true);
    setStatus(undefined);
    try {
      const list = await check;
      setModels(list);
      const chosen = !model || !list.includes(model) ? list[0] ?? PREFERRED[0] : model;
      setModel(chosen);
      setStatus(`Connected. Using ${chosen}.`);
    } catch (err) {
      if (err instanceof OpenAIError && err.status === 401) {
        setKey("");
        setStatus(err.message);
      } else {
        setStatus(`Saved. Couldn't verify it right now: ${describe(err)}`);
      }
    } finally {
      saving.current = false;
      setChecking(false);
    }
  }

  function clear() {
    setKey("");
    setDraft("");
    setModels([]);
    setStatus("Key removed from this browser.");
  }

  const options = [...new Set([...(models.length ? models : PREFERRED), ...(model ? [model] : [])])];

  return (
    <section className="card pad stack assistant-settings">
      <span className="eyebrow">Assistant</span>
      <div className="row" style={{ alignItems: "flex-start" }}>
        <span className="assistant-settings-icon"><Icon name="key" /></span>
        <span className="small muted">
          Ask questions about any page, word or photo. Answers come from OpenAI using your own API key.
        </span>
      </div>
      <form className="assistant-key-form" onSubmit={save} autoComplete="off">
        <input
          className="input"
          type="password"
          name="openai-api-key"
          placeholder={key ? `Saved · ends in ${key.slice(-4)} · paste a new key to replace it` : "sk-…"}
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          autoComplete="off"
          autoCapitalize="off"
          autoCorrect="off"
          spellCheck={false}
          aria-label="OpenAI API key"
        />
        <div className="row" style={{ ["--gap" as string]: "8px" }}>
          <button className="btn" type="submit" disabled={!draft.trim() || checking}>{checking ? "Checking…" : "Save"}</button>
          <button className="btn secondary" type="button" onClick={clear} disabled={!key || checking}>Clear</button>
        </div>
      </form>
      {status && <p className="small muted" role="status">{status}</p>}
      {key && (
        <label className="stack" style={{ ["--gap" as string]: "6px" }}>
          <span className="small" style={{ fontWeight: 600 }}>Model</span>
          <select className="input" value={model || options[0]} onChange={(e) => setModel(e.target.value)}>
            {options.map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        </label>
      )}
      <a className="small assistant-link" href="https://platform.openai.com/api-keys" target="_blank" rel="noopener noreferrer">
        Get a key at platform.openai.com
      </a>
      <p className="tiny faint">
        Your key stays in this browser's local storage and is only sent to api.openai.com, with the questions, page text and images you ask about.
      </p>
    </section>
  );
}
