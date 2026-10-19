import { Link } from "react-router-dom";
import { type Book, url, useStore } from "../content";
import { type Appearance, useAdvanced, useAppearance, useLibrary, useTextScale } from "../store";
import { BookCover, Icon, Pill, SectionHeader, Segmented, categoryTint, tintVar, tinted } from "../ui";
import { AssistantSettings, useAssistant } from "../features/assistant";

const SYMBOLS: Record<string, string> = { flask: "sparkles", shield: "check", brain: "bulb", algorithm: "graph", branch: "turn" };

function greeting() {
  const h = new Date().getHours();
  return h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
}

export function Home() {
  const store = useStore();
  const library = useLibrary();
  const { ask } = useAssistant();
  const recent = library.lib.recentBooks.map((id) => store.books.get(id)).filter((b): b is Book => !!b);
  const term = store.termOfTheDay;
  const fieldGuide = store.books.get("fellowship-00-field-guide");

  return (
    <div className="stack" style={{ ["--gap" as string]: "34px" }}>
      <header className="row" style={{ alignItems: "flex-end" }}>
        <div className="stack" style={{ ["--gap" as string]: "6px", flex: 1 }}>
          <span className="eyebrow">{new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</span>
          <h1 className="title-xl">{greeting()}</h1>
          <span className="muted">{store.pages.size} illustrated pages · {store.glossary.length} terms · {store.playbook?.experiments.length ?? 0} experiment maps</span>
        </div>
        <button className="iconbtn" aria-label="Ask the assistant" onClick={() => ask({ kind: "library" })}><Icon name="sparkles" /></button>
      </header>

      {recent.length ? (
        <section className="stack">
          <SectionHeader title="Continue" subtitle="Pick up where you left off" icon={<Icon name="bookmark" />} />
          <div className="hscroll">
            {recent.map((book) => <ContinueCard key={book.id} book={book} />)}
          </div>
        </section>
      ) : fieldGuide && (
        <section className="stack">
          <SectionHeader title="Start here" subtitle="A three-page field guide to research" icon={<Icon name="sparkles" />} />
          <ContinueCard book={fieldGuide} />
        </section>
      )}

      <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fit, minmax(260px, 1fr))" }}>
        <LinkCard to="/playbook" icon="map" tint={tintVar("violet")} title="Playbook" subtitle="Toolkit, experiment maps and drills" />
        <LinkCard to="/watch" icon="video" tint={tintVar("teal")} title="Watch" subtitle={`${store.videoBooks.length} narrated books`} />
        {library.lib.bookmarks.length > 0 && (
          <LinkCard to="/bookmarks" icon="bookmark" tint={tintVar("coral")} title="Saved pages" subtitle={`${library.lib.bookmarks.length} bookmarked`} />
        )}
      </div>

      {term && (
        <Link to={`/glossary/${term.id}`} className="card pad stack" style={{ ["--gap" as string]: "8px" }}>
          <span className="eyebrow" style={{ color: categoryTint(term.category) }}>Word of the day</span>
          <h2 className="title-l">{term.term}</h2>
          <p className="serif muted" style={{ fontSize: 17, fontStyle: "italic" }}>{term.short}</p>
        </Link>
      )}

      {store.collections.map((c) => (
        <section key={c.id} className="stack">
          <SectionHeader
            title={c.title}
            subtitle={c.subtitle}
            tint={tintVar(c.tint)}
            icon={<Icon name={SYMBOLS[c.symbol] ?? "books"} />}
            action={<Link to={`/c/${c.id}`} className="small" style={{ color: tintVar(c.tint), fontWeight: 600 }}>See all</Link>}
          />
          <div className="hscroll">
            {c.books.map((book) => <ShelfBook key={book.id} book={book} tint={tintVar(c.tint)} />)}
          </div>
        </section>
      ))}

      <p className="tiny faint" style={{ textAlign: "center" }}>Independent study guides. Proposed research is shown as proposals, not results.</p>
    </div>
  );
}

function LinkCard({ to, icon, tint, title, subtitle }: { to: string; icon: string; tint: string; title: string; subtitle: string }) {
  return (
    <Link to={to} className="card pad row" style={{ ["--gap" as string]: "14px" }}>
      <span className="row" style={{ width: 42, height: 42, borderRadius: 12, justifyContent: "center", color: tint, background: `color-mix(in srgb, ${tint} 14%, transparent)` }}>
        <Icon name={icon} size={20} />
      </span>
      <span className="stack" style={{ ["--gap" as string]: "2px", flex: 1 }}>
        <span className="serif" style={{ fontWeight: 600, fontSize: 17 }}>{title}</span>
        <span className="small muted">{subtitle}</span>
      </span>
      <Icon name="right" />
    </Link>
  );
}

function ContinueCard({ book }: { book: Book }) {
  const store = useStore();
  const library = useLibrary();
  const index = library.lastPageIndex(book);
  const page = book.pages[index];
  const collection = store.collectionFor(book);
  const tint = tintVar(collection?.tint ?? "teal");
  return (
    <Link to={`/read/${book.id}/${index}`} className="card row" style={{ ["--gap" as string]: "14px", padding: 14, minWidth: 300, maxWidth: 420, flexShrink: 0 }}>
      <BookCover book={book} width={78} />
      <span className="stack" style={{ ["--gap" as string]: "6px", flex: 1, minWidth: 0 }}>
        <span className="eyebrow" style={{ color: tint }}>{collection?.title}</span>
        <span className="serif" style={{ fontWeight: 600, fontSize: 18 }}>{book.title}</span>
        <span className="small muted">Page {index + 1} of {book.pages.length} · {page?.title}</span>
        <span className="progress" style={tinted(tint)}><div style={{ width: `${library.progress(book) * 100}%` }} /></span>
      </span>
    </Link>
  );
}

function ShelfBook({ book, tint }: { book: Book; tint: string }) {
  const library = useLibrary();
  const progress = library.progress(book);
  return (
    <Link to={`/b/${book.id}`} className="stack" style={{ ["--gap" as string]: "6px", width: 128, flexShrink: 0 }}>
      <BookCover book={book} width={128} />
      <span className="serif small" style={{ fontWeight: 600, lineHeight: 1.25 }}>{book.title}</span>
      <span className="tiny faint">{book.pages.length} pages{book.hasVideo ? " · video" : ""}</span>
      {progress > 0 && <span className="progress" style={tinted(tint)}><div style={{ width: `${progress * 100}%` }} /></span>}
    </Link>
  );
}

export function Bookmarks() {
  const store = useStore();
  const library = useLibrary();
  const pages = library.lib.bookmarks.map((id) => store.pages.get(id)).filter((p) => !!p);
  return (
    <div className="narrow stack">
      <h1 className="title-l">Saved pages</h1>
      {!pages.length && <p className="muted">Bookmark a page from the reader to find it here.</p>}
      {pages.map((page) => {
        const book = store.bookFor(page!)!;
        return (
          <Link key={page!.id} to={`/read/${book.id}/${book.pages.indexOf(page!)}`} className="card row" style={{ padding: 12, ["--gap" as string]: "14px" }}>
            <img src={url(page!.thumb)} alt="" style={{ width: 56, height: 84, objectFit: "cover", borderRadius: 8 }} loading="lazy" />
            <span className="stack" style={{ ["--gap" as string]: "3px" }}>
              <span className="serif" style={{ fontWeight: 600 }}>{page!.title}</span>
              <span className="small muted">{book.title} · page {page!.number}</span>
            </span>
          </Link>
        );
      })}
    </div>
  );
}

export function Settings() {
  const [appearance, setAppearance] = useAppearance();
  const [scale, setScale] = useTextScale();
  const [advanced, setAdvanced] = useAdvanced();
  const library = useLibrary();
  return (
    <div className="narrow stack" style={{ ["--gap" as string]: "18px" }}>
      <h1 className="title-l">Settings</h1>
      <section className="card pad stack">
        <span className="eyebrow">Appearance</span>
        <Segmented<Appearance> value={appearance} options={["system", "light", "dark"]} onChange={setAppearance} labels={{ system: "System", light: "Light", dark: "Dark" }} />
      </section>
      <section className="card pad stack">
        <label className="row" style={{ justifyContent: "space-between" }}>
          <span className="stack" style={{ ["--gap" as string]: "4px" }}>
            <span style={{ fontWeight: 600 }}>Advanced mode</span>
            <span className="small muted">Swaps the plain explanations for expert-level ones on text pages and in the glossary, and adds a closing note after each quiz answer. You can also switch it on any page.</span>
          </span>
          <input type="checkbox" checked={advanced} onChange={(e) => setAdvanced(e.target.checked)} style={{ width: 22, height: 22 }} />
        </label>
      </section>
      <section className="card pad stack">
        <span className="eyebrow">Reading text size</span>
        <input type="range" min={0.85} max={1.6} step={0.05} value={scale} onChange={(e) => setScale(Number(e.target.value))} />
        <p className="serif muted" style={{ fontSize: 18 * scale }}>Reinforcement learning from human feedback is like practising with a coach.</p>
      </section>
      <AssistantSettings />
      <section className="card pad stack">
        <span className="eyebrow">Your progress</span>
        <div className="row"><span>Pages read</span><span className="spacer" /><span className="muted">{library.lib.readPages.length}</span></div>
        <div className="row"><span>Saved pages</span><span className="spacer" /><span className="muted">{library.lib.bookmarks.length}</span></div>
        <button className="btn secondary" style={tinted(tintVar("coral"))} onClick={library.clearSearches}>Clear search history</button>
      </section>
      <p className="small faint">Progress, bookmarks and settings stay in this browser.</p>
      <Pill text="Safety Atlas · web" />
    </div>
  );
}
