// Reader: one page at a time in Comic / Text / Video mode (port of ReaderView.swift + ReaderPage.swift).
import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { type Book, type Page, url, useStore } from "../content";
import { type ReaderMode, useAdvanced, useLibrary, useReaderMode, useTextScale } from "../store";
import { Icon, Linked, Segmented, TermChip, linkAll, termsIn, tintVar, tinted } from "../ui";
import { useListen } from "../features/listen";
import { useAssistant } from "../features/assistant";
import "./reader.css";

const SIMPLER = "Explain this page more simply, like I'm 12, with one everyday analogy, in under 150 words.";

export function Reader() {
  const store = useStore();
  const navigate = useNavigate();
  const { bookId, index: indexParam } = useParams();
  const [params, setParams] = useSearchParams();
  const [savedMode, setSavedMode] = useReaderMode();
  const [advanced, setAdvanced] = useAdvanced();
  const library = useLibrary();
  const listen = useListen();
  const { ask } = useAssistant();
  const [menu, setMenu] = useState(false);
  const [zoomed, setZoomed] = useState(false);

  const book = store.books.get(bookId ?? "");
  const index = Math.min(Math.max(Number(indexParam ?? 0) || 0, 0), Math.max((book?.pages.length ?? 1) - 1, 0));
  const page = book?.pages[index];
  const modes: ReaderMode[] = book?.hasVideo ? ["comic", "text", "video"] : ["comic", "text"];
  const wanted = (params.get("mode") as ReaderMode) || savedMode;
  const mode: ReaderMode = modes.includes(wanted) ? wanted : "comic";

  useEffect(() => { if (book) library.open(book, index); }, [book?.id, index]); // eslint-disable-line react-hooks/exhaustive-deps
  useEffect(() => { setZoomed(false); window.scrollTo(0, 0); }, [index, mode]);

  const go = (i: number) => {
    if (!book || i < 0 || i >= book.pages.length) return;
    navigate(`/read/${book.id}/${i}${params.get("mode") ? `?mode=${mode}` : ""}`, { replace: true });
  };
  const setMode = (m: ReaderMode) => {
    setSavedMode(m);
    const next = new URLSearchParams(params);
    next.set("mode", m);
    setParams(next, { replace: true });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.target as HTMLElement)?.closest("input, textarea")) return;
      if (e.key === "ArrowRight") go(index + 1);
      if (e.key === "ArrowLeft") go(index - 1);
      if (e.key === "Escape" && book) navigate(`/b/${book.id}`);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  // Horizontal swipe turns pages on touch screens (not while zoomed into a comic).
  const touch = useRef<{ x: number; y: number } | null>(null);
  const onTouchStart = (e: React.TouchEvent) => { touch.current = { x: e.touches[0].clientX, y: e.touches[0].clientY }; };
  const onTouchEnd = (e: React.TouchEvent) => {
    if (!touch.current || zoomed) return;
    const dx = e.changedTouches[0].clientX - touch.current.x;
    const dy = e.changedTouches[0].clientY - touch.current.y;
    touch.current = null;
    if (Math.abs(dx) > 70 && Math.abs(dx) > Math.abs(dy) * 1.5) go(index + (dx < 0 ? 1 : -1));
  };

  if (!book || !page) return <main className="main narrow"><p className="muted">Page not found.</p><Link to="/" className="btn">Back to the library</Link></main>;
  const collection = store.collectionFor(book);
  const tint = tintVar(collection?.tint ?? "teal");
  const listeningHere = listen.isActive && book.pages.some((p) => p.id === listen.pageId);
  const askPage = (prompt?: string) => { setMenu(false); ask({ kind: "page", pageId: page.id, showingComic: mode === "comic" }, prompt); };

  return (
    <div className={`reader mode-${mode}`} style={tinted(tint)} onTouchStart={onTouchStart} onTouchEnd={onTouchEnd}>
      <div className="reader-top">
        <Link to={`/b/${book.id}`} className="iconbtn" aria-label="Close"><Icon name="close" /></Link>
        <div className="reader-modes">
          <Segmented<ReaderMode> value={mode} options={modes} onChange={setMode} labels={{ comic: "Comic", text: "Text", video: "Video" }} />
        </div>
        <span className="spacer" />
        <button className={`iconbtn${advanced ? " on" : ""}`} aria-label={advanced ? "Back to beginner" : "Advanced mode"} title={advanced ? "Back to beginner" : "Advanced mode"}
          onClick={() => { setAdvanced(!advanced); if (!advanced && mode === "comic") setMode("text"); }}>
          <Icon name="grad" />
        </button>
        <div style={{ position: "relative" }}>
          <button className="iconbtn" aria-label="Ask or explain" onClick={() => setMenu(!menu)}><Icon name="sparkles" /></button>
          {menu && (
            <div className="reader-menu card" onMouseLeave={() => setMenu(false)}>
              <button onClick={() => askPage()}>Ask a question</button>
              <button onClick={() => askPage(SIMPLER)}>Explain it simpler</button>
              <button onClick={() => askPage("Give me one concrete, real-world example of the main idea on this page, in under 120 words.")}>Real-world example</button>
              <button onClick={() => askPage("Quiz me on this page: ask one question at a time, wait for my answer, then tell me if I'm right.")}>Quiz me on this page</button>
            </div>
          )}
        </div>
        <button className={`iconbtn${listeningHere ? " on" : ""}`} aria-label="Listen from this page"
          onClick={() => (listeningHere ? listen.toggle() : listen.start(book, index))}>
          <Icon name={listeningHere && listen.isPlaying ? "pause" : "headphones"} />
        </button>
        <button className={`iconbtn${library.isBookmarked(page) ? " on" : ""}`} aria-label="Bookmark" onClick={() => library.toggleBookmark(page)}>
          <Icon name="bookmark" />
        </button>
      </div>

      {mode === "comic" && (
        <div className={`comic${zoomed ? " zoomed" : ""}`} onClick={() => setZoomed(!zoomed)} title={zoomed ? "Click to fit" : "Click to zoom"}>
          <img src={url(page.image)} alt={`Comic page: ${page.title}`} />
        </div>
      )}
      {mode === "text" && <TextPage page={page} book={book} tint={tint} />}
      {mode === "video" && <VideoPage page={page} book={book} />}

      <div className="reader-bottom">
        <button className="iconbtn" aria-label="Previous page" disabled={index === 0} onClick={() => go(index - 1)}><Icon name="left" /></button>
        <div className="stack" style={{ ["--gap" as string]: "4px", flex: 1, minWidth: 0, textAlign: "center" }}>
          <span className="serif" style={{ fontWeight: 600, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{page.title}</span>
          <span className="tiny faint">{book.title} · {index + 1} of {book.pages.length}</span>
          <input type="range" min={0} max={book.pages.length - 1} value={index} onChange={(e) => go(Number(e.target.value))} aria-label="Page" />
        </div>
        <button className="iconbtn" aria-label="Next page" disabled={index === book.pages.length - 1} onClick={() => go(index + 1)}><Icon name="right" /></button>
      </div>
    </div>
  );
}

function TextPage({ page, book, tint }: { page: Page; book: Book; tint: string }) {
  const store = useStore();
  const [advanced, setAdvanced] = useAdvanced();
  const [scale] = useTextScale();
  const listen = useListen();
  const skip = useMemo(() => store.termsToSkip(book), [store, book]);
  const deeper = advanced && page.deeper?.panels.length === page.panels.length ? page.deeper : undefined;
  // Beginner text and advanced notes each link a term at its first mention.
  const beginnerLinks = useMemo(() => linkAll(store, page.panels.map((p) => p.body), skip), [store, page, skip]);
  const deeperParas = useMemo(() => (page.deeper?.panels ?? []).map((t) => t.split("\n\n")), [page]);
  const deeperLinks = useMemo(() => {
    const flat = linkAll(store, deeperParas.flat(), skip);
    let k = 0;
    return deeperParas.map((paras) => paras.map(() => flat[k++]));
  }, [store, deeperParas, skip]);
  const terms = termsIn(store, page.panels.map((p) => p.body), skip);

  return (
    <article className="text-page" style={{ ["--scale" as string]: scale }}>
      <span className="eyebrow" style={{ color: tint }}>Page {page.number} · {book.title}</span>
      <h1 className="text-title">{page.title}</h1>
      {page.subtitle && <p className="text-subtitle">{page.subtitle}</p>}
      <div className="ornament"><span /><Icon name="sparkles" size={11} /><span /></div>

      {page.deeper && (
        <div style={{ marginBottom: 24 }}>
          <Segmented value={advanced ? "advanced" : "beginner"} options={["beginner", "advanced"] as const}
            onChange={(v) => setAdvanced(v === "advanced")} labels={{ beginner: "Beginner", advanced: "Advanced" }} />
        </div>
      )}

      {page.wordKey && (
        <div className="word-key"><span className="eyebrow" style={{ color: tint }}>Word key</span><p>{page.wordKey}</p></div>
      )}
      {!page.panels.length && <p className="text-body muted">{page.summary || "This page is best read as a comic."}</p>}

      {page.panels.map((panel, i) => {
        const speaking = listen.pageId === page.id && listen.panel === i;
        const beginner = <Linked text={panel.body} matches={beginnerLinks[i]} tint={tint} />;
        return (
          <section key={i} className={`panel${speaking ? " speaking" : ""}`}>
            <div className="panel-head">
              <span className="panel-num">{panel.number}</span>
              <h2>{panel.heading}</h2>
            </div>
            {deeper ? (
              <>
                <span className="pill" style={{ alignSelf: "flex-start" }}>ADVANCED</span>
                {deeperParas[i].map((para, j) => (
                  <p key={j} className="text-body"><Linked text={para} matches={deeperLinks[i][j]} tint={tint} /></p>
                ))}
                <details className="beginner-version">
                  <summary><Icon name="bulb" size={15} />Beginner version</summary>
                  <p>{beginner}</p>
                </details>
              </>
            ) : (
              panel.body && <p className="text-body">{beginner}</p>
            )}
            {panel.code && <pre className="code">{panel.code}</pre>}
          </section>
        );
      })}

      {deeper?.further && (
        <div className="deeper-note">
          <span className="eyebrow" style={{ color: tint }}>Beyond the basics</span>
          <p>{deeper.further}</p>
        </div>
      )}
      {page.sources && page.sources.length > 0 && (
        <div className="deeper-note">
          <span className="eyebrow" style={{ color: tint }}>Readings</span>
          <ul className="sources">
            {page.sources.map((s) => <li key={s.url}><a href={s.url} target="_blank" rel="noopener noreferrer">{s.title}</a></li>)}
          </ul>
        </div>
      )}
      {page.footer && <blockquote className="pull-quote"><span />{page.footer}<span /></blockquote>}

      {terms.length > 0 && (
        <div className="stack" style={{ ["--gap" as string]: "12px", marginTop: 28 }}>
          <span className="small muted" style={{ fontWeight: 600 }}>Words on this page</span>
          <div className="wrap">{terms.map((t) => <TermChip key={t.id} term={t} short />)}</div>
        </div>
      )}
    </article>
  );
}

function VideoPage({ page, book }: { page: Page; book: Book }) {
  const clips = book.pages.filter((p) => p.video);
  if (!page.video) return <div className="text-page"><p className="muted">No video for this page. Switch to Comic or Text to read it.</p></div>;
  return (
    <div className="video-page">
      <video key={page.id} src={url(page.video)} poster={page.poster ? url(page.poster) : undefined} controls autoPlay playsInline />
      <span className="eyebrow" style={{ color: "var(--tint)" }}>Clip {clips.indexOf(page) + 1} of {clips.length}</span>
      <h1 className="title-l">{page.title}</h1>
      {page.subtitle && <p className="serif muted" style={{ fontStyle: "italic" }}>{page.subtitle}</p>}
      <Link to={`/watch?book=${book.id}`} className="btn secondary">Play the whole book</Link>
      {page.summary && <p className="serif muted">{page.summary}</p>}
    </div>
  );
}
