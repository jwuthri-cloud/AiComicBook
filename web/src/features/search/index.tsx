// Search (port of SearchView.swift). The query lives in ?q= so results are linkable.
import { useDeferredValue, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { type Page, url, useStore } from "../../content";
import { useLibrary } from "../../store";
import { BookCover, Icon, Segmented, categoryTint, tinted, tintVar } from "../../ui";
import { themeIcon, themeTint, toolIcon, toolTint, XIcon } from "../playbook/style";
import { engineFor, type Hit, snippet, wordMatches } from "./engine";
import "./search.css";

const SCOPES = ["All", "Pages", "Words", "Books", "Playbook"] as const;
type Scope = (typeof SCOPES)[number];

const SUGGESTIONS = [
  "How can a model cheat on its tests?", "RLHF", "sliding window", "What is a probe?",
  "sparse autoencoder", "git rebase", "why freeze the monitor", "dynamic programming",
];

const COLLECTION_ICONS: Record<string, string> = { flask: "flask", shield: "shield", brain: "brain", algorithm: "graph", branch: "branch" };

const inScope = (hit: Hit, scope: Scope) =>
  scope === "All" ||
  (scope === "Pages" && hit.kind === "page") ||
  (scope === "Words" && hit.kind === "term") ||
  (scope === "Books" && hit.kind === "book") ||
  (scope === "Playbook" && (hit.kind === "tool" || hit.kind === "experiment"));

export function SearchPage() {
  const store = useStore();
  const library = useLibrary();
  const [params, setParams] = useSearchParams();
  const urlQuery = params.get("q") ?? "";
  const [text, setText] = useState(urlQuery);
  const [scope, setScope] = useState<Scope>("All");
  const inputRef = useRef<HTMLInputElement>(null);
  const pushed = useRef(urlQuery);

  // Back/forward or a shared link changed ?q=: follow it (but not our own keystrokes echoing back).
  useEffect(() => {
    if (urlQuery !== pushed.current) {
      pushed.current = urlQuery;
      setText(urlQuery);
    }
  }, [urlQuery]);

  const setQuery = (q: string, push = false) => {
    setText(q);
    pushed.current = q;
    setParams(q ? { q } : {}, { replace: !push });
  };

  const deferred = useDeferredValue(text);
  const hits = useMemo(() => (deferred.trim() ? engineFor(store).search(deferred) : []), [store, deferred]);
  const remember = () => library.remember(text);

  return (
    <div className="narrow stack" style={{ ["--gap" as string]: "20px" }}>
      <h1 className="title-xl">Search</h1>
      <form
        role="search"
        className="sr-field"
        onSubmit={(e) => {
          e.preventDefault();
          remember();
          inputRef.current?.blur();
        }}
      >
        <Icon name="search" size={18} />
        <input
          ref={inputRef}
          className="input"
          type="search"
          value={text}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Pages, ideas, words…"
          aria-label="Search pages, ideas and words"
          autoFocus={!urlQuery}
          autoComplete="off"
          enterKeyHint="search"
        />
      </form>
      {text.trim() ? (
        <Results hits={hits} query={text} scope={scope} setScope={setScope} onOpen={remember} />
      ) : (
        <Idle onPick={(q) => setQuery(q, true)} />
      )}
    </div>
  );
}

// ---------- idle state ----------

function Idle({ onPick }: { onPick: (q: string) => void }) {
  const store = useStore();
  const { lib, clearSearches } = useLibrary();
  return (
    <div className="stack" style={{ ["--gap" as string]: "28px" }}>
      {lib.recentSearches.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "12px" }}>
          <div className="row">
            <h2 className="sr-h2">Recent</h2>
            <span className="spacer" />
            <button className="sr-link-btn" onClick={clearSearches}>Clear</button>
          </div>
          <div className="wrap">
            {lib.recentSearches.map((q) => (
              <button key={q} className="sr-recent" onClick={() => onPick(q)}>
                <XIcon name="clock" size={15} />
                {q}
              </button>
            ))}
          </div>
        </section>
      )}

      <section className="stack" style={{ ["--gap" as string]: "12px" }}>
        <div className="stack" style={{ ["--gap" as string]: "4px" }}>
          <h2 className="sr-h2">Try asking</h2>
          <p className="small muted">Search understands typos, acronyms and plain questions.</p>
        </div>
        <div className="wrap">
          {SUGGESTIONS.map((s) => (
            <button key={s} className="sr-suggestion" onClick={() => onPick(s)}>{s}</button>
          ))}
        </div>
      </section>

      <section className="stack" style={{ ["--gap" as string]: "12px" }}>
        <h2 className="sr-h2">Browse</h2>
        <div className="sr-tiles">
          {store.collections.map((c) => (
            <Link key={c.id} to={`/c/${c.id}`} className="sr-tile" style={tinted(tintVar(c.tint))}>
              <span className="sr-tile-icon"><XIcon name={COLLECTION_ICONS[c.symbol] ?? "books"} size={20} /></span>
              <span className="spacer" />
              <span className="sr-tile-title">{c.title}</span>
              <span className="tiny muted">{c.pageCount} pages</span>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}

// ---------- results ----------

function Results({ hits, query, scope, setScope, onOpen }: { hits: Hit[]; query: string; scope: Scope; setScope: (s: Scope) => void; onOpen: () => void }) {
  const items = hits.filter((h) => inScope(h, scope));
  const top = scope === "All" ? items[0] : undefined;
  const rest = top ? items.slice(1) : items;
  const words = rest.filter((h) => h.kind === "term");
  const pages = rest.filter((h) => h.kind === "page");
  const books = rest.filter((h) => h.kind === "book");
  const playbook = rest.filter((h) => h.kind === "tool" || h.kind === "experiment");
  const row = (h: Hit, prominent = false) => <ResultRow key={h.key} hit={h} prominent={prominent} onOpen={onOpen} />;

  return (
    <div className="stack" style={{ ["--gap" as string]: "22px" }}>
      <div className="sr-scopes">
        <Segmented value={scope} options={SCOPES} onChange={setScope} />
      </div>
      {!items.length ? (
        <div className="sr-empty">
          <span className="faint"><Icon name="search" size={36} /></span>
          <h2 className="title-m">No results for “{query.trim()}”</h2>
          <p className="small muted">Check the spelling or try a new search.</p>
        </div>
      ) : (
        <>
          {top && <Section title="Top result">{row(top, true)}</Section>}
          {words.length > 0 && <Section title="Words">{words.slice(0, 8).map((h) => row(h))}</Section>}
          {pages.length > 0 && <Section title="Pages">{pages.slice(0, 30).map((h) => row(h))}</Section>}
          {books.length > 0 && <Section title="Books">{books.slice(0, 6).map((h) => row(h))}</Section>}
          {playbook.length > 0 && <Section title="Playbook">{playbook.slice(0, 10).map((h) => row(h))}</Section>}
        </>
      )}
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="stack" style={{ ["--gap" as string]: "8px" }}>
      <h2 className="sr-section-title">{title}</h2>
      <div className="card sr-list">{children}</div>
    </section>
  );
}

function ResultRow({ hit, prominent, onOpen }: { hit: Hit; prominent: boolean; onOpen: () => void }) {
  const store = useStore();
  const cls = `sr-row${prominent ? " prominent" : ""}`;
  switch (hit.kind) {
    case "term": {
      const term = store.terms.get(hit.itemId);
      if (!term) return null;
      return (
        <Link to={`/glossary/${term.id}`} className={cls} onClick={onOpen}>
          <span className="sr-text">
            <span className="sr-title-line">
              <span className="sr-title">{term.term}</span>
              {term.aka.slice(0, 2).map((a) => (
                <span key={a} className="sr-aka" style={tinted(categoryTint(term.category))}>{a}</span>
              ))}
            </span>
            <span className={`sr-snippet clamp-${prominent ? 3 : 2}`}>{term.short}</span>
          </span>
        </Link>
      );
    }
    case "page": {
      const page = store.pages.get(hit.itemId);
      const book = page && store.bookFor(page);
      if (!page || !book) return null;
      const index = Math.max(0, book.pages.findIndex((p) => p.id === page.id));
      return (
        <Link to={`/read/${book.id}/${index}`} className={cls} onClick={onOpen}>
          <img className="sr-thumb" src={url(page.thumb)} alt="" loading="lazy" />
          <span className="sr-text">
            <span className="sr-eyebrow">{book.title}</span>
            <span className="sr-title">{page.title}</span>
            <PageSnippet page={page} tokens={hit.matched} lines={prominent ? 4 : 3} />
          </span>
        </Link>
      );
    }
    case "book": {
      const book = store.books.get(hit.itemId);
      if (!book) return null;
      return (
        <Link to={`/b/${book.id}`} className={`${cls} center`} onClick={onOpen}>
          <BookCover book={book} width={prominent ? 56 : 44} />
          <span className="sr-text">
            <span className="sr-title">{book.title}</span>
            <span className="tiny muted">{store.collectionFor(book)?.title ?? ""} · {book.pages.length} pages</span>
          </span>
          <span className="sr-chevron"><Icon name="right" size={15} /></span>
        </Link>
      );
    }
    case "tool": {
      const tool = store.tools.get(hit.itemId);
      if (!tool) return null;
      return (
        <Link to={`/playbook/tool/${tool.id}`} className={cls} onClick={onOpen} style={tinted(toolTint(tool.category))}>
          <span className="sr-badge"><XIcon name={toolIcon(tool.category)} size={18} /></span>
          <span className="sr-text">
            <span className="sr-eyebrow tinted">Tool · {tool.category}</span>
            <span className="sr-title">{tool.name}</span>
            <span className={`sr-snippet clamp-${prominent ? 3 : 2}`}>{tool.what}</span>
          </span>
        </Link>
      );
    }
    case "experiment": {
      const e = store.playbook?.experiments.find((x) => x.id === hit.itemId);
      if (!e) return null;
      return (
        <Link to={`/playbook/experiment/${e.id}`} className={cls} onClick={onOpen} style={tinted(themeTint(e.theme))}>
          <span className="sr-badge"><XIcon name={themeIcon(e.theme)} size={18} /></span>
          <span className="sr-text">
            <span className="sr-eyebrow tinted">Experiment · {e.theme}</span>
            <span className="sr-title">{e.question}</span>
            <span className={`sr-snippet clamp-${prominent ? 3 : 2}`}>{e.chain}</span>
          </span>
        </Link>
      );
    }
  }
}

/** Excerpt around the first matched word, with matched words in bold. */
function PageSnippet({ page, tokens, lines }: { page: Page; tokens: Set<string>; lines: number }) {
  const source = [page.subtitle, page.summary, ...page.panels.map((p) => p.body)].join(" ");
  const words = snippet(source, tokens).split(" ");
  return (
    <span className={`sr-snippet clamp-${lines}`}>
      {words.map((w, i) => (
        <span key={i}>
          {i > 0 && " "}
          {wordMatches(w, tokens) ? <b>{w}</b> : w}
        </span>
      ))}
    </span>
  );
}
