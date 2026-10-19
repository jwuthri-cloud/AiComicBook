// Glossary list, term detail and concept map (port of GlossaryView.swift and ConceptMapView.swift).
import { useEffect, useMemo, useRef } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { type Page, type Term, url, useStore } from "../../content";
import { useAdvanced } from "../../store";
import { Icon, Pill, Segmented, TermChip, categoryTint, tintVar, tinted } from "../../ui";
import { useAssistant } from "../assistant";
import { GIcon } from "./icons";
import { canGoBack, matchesTerm, plural, sortLetter } from "./logic";
import "./glossary.css";

export { ConceptMapPage } from "./ConceptMap";

// ---------- list ----------

export function GlossaryPage() {
  const store = useStore();
  const [params, setParams] = useSearchParams();
  const filter = params.get("q") ?? "";
  const category = params.get("cat");
  const input = useRef<HTMLInputElement>(null);

  // Search and topic live in the URL so coming back from a term restores the list.
  const update = (q: string, cat: string | null) => {
    const next = new URLSearchParams();
    if (q) next.set("q", q);
    if (cat) next.set("cat", cat);
    setParams(next, { replace: true });
  };

  const categories = useMemo(() => [...new Set(store.glossary.map((t) => t.category))].sort(), [store]);
  const q = filter.trim();
  const terms = store.glossary.filter((t) => (!category || t.category === category) && (!q || matchesTerm(t, q)));
  const groups = new Map<string, Term[]>();
  for (const t of terms) {
    const letter = sortLetter(t);
    groups.set(letter, [...(groups.get(letter) ?? []), t]);
  }
  const letters = [...groups.keys()].sort();

  // "/" jumps to the search field, like most sites with a search box.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement;
      if (e.key !== "/" || e.metaKey || e.ctrlKey || el.closest("input, textarea, [contenteditable=true]")) return;
      e.preventDefault();
      input.current?.focus();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, []);

  const mapId = store.termOfTheDay?.id ?? store.glossary[0]?.id ?? "";

  return (
    <div className="narrow stack gl-page">
      <header className="stack" style={{ ["--gap" as string]: "4px" }}>
        <h1 className="title-xl">Glossary</h1>
        <span className="small muted">{store.glossary.length} words and acronyms, from beginner to advanced</span>
      </header>

      <div className="gl-search">
        <Icon name="search" />
        <input
          ref={input}
          className="input"
          type="text"
          inputMode="search"
          enterKeyHint="search"
          autoComplete="off"
          spellCheck={false}
          placeholder="Find a word or acronym"
          aria-label="Find a word or acronym"
          value={filter}
          onChange={(e) => update(e.target.value, category)}
          onKeyDown={(e) => { if (e.key === "Escape") update("", category); }}
        />
        {filter && (
          <button className="gl-clear" aria-label="Clear search" onClick={() => { update("", category); input.current?.focus(); }}>
            <Icon name="close" size={14} />
          </button>
        )}
      </div>

      {!filter && (
        <div className="gl-tools">
          <ToolCard to={`/map/${mapId}`} icon="graph" tint={tintVar("violet")} title="Concept map" subtitle="See how words connect" />
          <ToolCard to="/flashcards" icon="cards" tint={tintVar("teal")} title="Flashcards" subtitle="Flip, swipe, remember" />
        </div>
      )}

      <div className="hscroll gl-chips" role="group" aria-label="Filter by topic">
        <CategoryChip text="All" selected={!category} tint="var(--accent)" onClick={() => update(filter, null)} />
        {categories.map((c) => (
          <CategoryChip key={c} text={c} selected={category === c} tint={categoryTint(c)} onClick={() => update(filter, category === c ? null : c)} />
        ))}
      </div>

      {terms.length === 0 ? (
        <div className="gl-empty">
          <Icon name="search" size={44} />
          <h2 className="title-m">No results for “{q}”</h2>
          <p className="small muted">Check the spelling or try a new search.</p>
        </div>
      ) : (
        letters.map((letter) => (
          <section key={letter} className="stack" style={{ ["--gap" as string]: "8px" }} aria-label={letter}>
            <h2 className="gl-letter">{letter}</h2>
            <div className="card gl-list">
              {groups.get(letter)!.map((t) => <TermRow key={t.id} term={t} />)}
            </div>
          </section>
        ))
      )}
    </div>
  );
}

function ToolCard({ to, icon, tint, title, subtitle }: { to: string; icon: string; tint: string; title: string; subtitle: string }) {
  return (
    <Link to={to} className="card gl-tool" style={tinted(tint)}>
      <span className="gl-tool-icon"><Icon name={icon} size={18} /></span>
      <span className="serif gl-tool-title">{title}</span>
      <span className="tiny muted gl-ellipsis">{subtitle}</span>
    </Link>
  );
}

function CategoryChip({ text, selected, tint, onClick }: { text: string; selected: boolean; tint: string; onClick: () => void }) {
  return (
    <button className={`chip gl-chip${selected ? " selected" : ""}`} style={tinted(tint)} aria-pressed={selected} onClick={onClick}>
      {text}
    </button>
  );
}

export function TermRow({ term, prominent }: { term: Term; prominent?: boolean }) {
  return (
    <Link to={`/glossary/${term.id}`} className="gl-row" style={tinted(categoryTint(term.category))}>
      <span className="gl-row-text">
        <span className="gl-row-head">
          <span className={`serif gl-row-name${prominent ? " prominent" : ""}`}>{term.term}</span>
          {term.aka.slice(0, 2).map((a) => <span key={a} className="gl-aka">{a}</span>)}
        </span>
        <span className={`serif gl-row-short${prominent ? " prominent" : ""}`}>{term.short}</span>
      </span>
      <span className="faint"><Icon name="right" size={16} /></span>
    </Link>
  );
}

// ---------- term detail ----------

export function TermPage() {
  const { termId = "" } = useParams();
  const store = useStore();
  const term = store.terms.get(termId);
  if (!term) {
    return (
      <div className="narrow stack">
        <h1 className="title-l">Word not found</h1>
        <p className="muted">There is no glossary entry called “{termId}”.</p>
        <Link to="/glossary" className="btn secondary" style={{ alignSelf: "flex-start" }}>Open the glossary</Link>
      </div>
    );
  }
  return <TermDetail key={term.id} term={term} />;
}

const paragraphs = (text: string) => text.split(/\n\s*\n/).map((p) => p.trim()).filter(Boolean);

function TermDetail({ term }: { term: Term }) {
  const store = useStore();
  const navigate = useNavigate();
  const [advanced, setAdvanced] = useAdvanced();
  const { ask } = useAssistant();
  const tint = categoryTint(term.category);
  const related = term.related.map((id) => store.terms.get(id)).filter((t): t is Term => !!t);
  const pages = term.pages.map((id) => store.pages.get(id)).filter((p): p is Page => !!p);
  const deep = term.advanced;
  const showDeep = !!deep && advanced;

  return (
    <article className="narrow stack gl-term" style={{ ["--gap" as string]: "22px", ...tinted(tint) }}>
      <button className="gl-back" onClick={() => (canGoBack() ? navigate(-1) : navigate("/glossary"))}>
        <Icon name="left" size={16} />Glossary
      </button>

      <header className="stack" style={{ ["--gap" as string]: "10px" }}>
        <span><Pill text={term.category} tint={tint} /></span>
        <h1 className="title-xl gl-term-title">{term.term}</h1>
        {term.aka.length > 0 && <p className="small muted gl-also">Also: {term.aka.join(" · ")}</p>}
      </header>

      <p className="serif gl-short">{term.short}</p>

      {deep && (
        <Segmented
          value={advanced ? "advanced" : "beginner"}
          options={["beginner", "advanced"] as const}
          labels={{ beginner: "Beginner", advanced: "Advanced" }}
          onChange={(v) => setAdvanced(v === "advanced")}
        />
      )}

      {showDeep ? (
        <>
          <div className="stack" style={{ ["--gap" as string]: "14px" }}>
            <span className="gl-adv-tag">Advanced</span>
            {paragraphs(deep).map((p, i) => <p key={i} className="body-text gl-body">{p}</p>)}
          </div>
          <details className="gl-beginner">
            <summary><GIcon name="bulb" size={16} />Beginner version<span className="gl-caret"><Icon name="down" size={14} /></span></summary>
            <div className="stack" style={{ ["--gap" as string]: "10px", marginTop: 10 }}>
              {paragraphs(term.definition).map((p, i) => <p key={i} className="serif muted gl-beginner-text">{p}</p>)}
            </div>
          </details>
        </>
      ) : (
        <div className="stack" style={{ ["--gap" as string]: "14px" }}>
          {paragraphs(term.definition).map((p, i) => <p key={i} className="body-text gl-body">{p}</p>)}
        </div>
      )}

      <div className="wrap">
        <button
          className="chip gl-action"
          style={tinted(tint)}
          onClick={() => ask({ kind: "term", termId: term.id }, `Explain “${term.term}” like I'm 12, with one everyday analogy, in under 100 words.`)}
        >
          <GIcon name="sparkles" size={16} />Explain simpler
        </button>
        <button className="chip gl-action" style={tinted(tint)} onClick={() => ask({ kind: "term", termId: term.id })}>
          <GIcon name="bubble" size={16} />Ask about it
        </button>
        <Link to={`/map/${term.id}`} className="chip gl-action" style={tinted(tint)}>
          <GIcon name="graph" size={16} />See on map
        </Link>
      </div>

      {related.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "10px" }}>
          <h2 className="gl-h">Related</h2>
          <div className="wrap">
            {related.map((r) => <TermChip key={r.id} term={r} />)}
          </div>
        </section>
      )}

      {pages.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "12px" }}>
          <h2 className="gl-h">Appears in {plural(pages.length, "page")}</h2>
          <div className="hscroll gl-pages">
            {pages.map((page) => <PageThumb key={page.id} page={page} />)}
          </div>
        </section>
      )}
    </article>
  );
}

function PageThumb({ page }: { page: Page }) {
  const store = useStore();
  const book = store.bookFor(page);
  const index = Math.max(0, book?.pages.findIndex((p) => p.id === page.id) ?? 0);
  return (
    <Link to={`/read/${page.bookId}/${index}`} className="gl-thumb">
      <img src={url(page.thumb)} alt="" loading="lazy" />
      <span className="serif gl-thumb-title">{page.title}</span>
      <span className="tiny faint gl-ellipsis">{book?.title}</span>
    </Link>
  );
}
