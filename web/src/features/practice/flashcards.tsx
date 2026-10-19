// Glossary flashcards (port of FlashcardsView.swift): click or press Space to flip, swipe or use the arrow keys —
// right if you knew it, left to see it again. Answers feed the same review boxes as the other practice modes.
import { useEffect, useRef, useState, type KeyboardEvent as ReactKeyboardEvent, type PointerEvent as ReactPointerEvent } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { type Store, type Term, useStore } from "../../content";
import { useLibrary } from "../../store";
import { Icon, Pill, categoryTint, tintVar, tinted } from "../../ui";
import { type PracticeSnapshot, isMastered, meaningId, shuffled, usePractice, weighted } from "./progress";
import { GameFrame, PIcon, typingIn, useBack } from "./shared";

// ---------- decks ----------

function fromReading(store: Store, readPages: string[]): Term[] {
  const read = new Set(readPages);
  return store.glossary.filter((t) => t.pages.some((id) => read.has(id)));
}

function buildDeck(deck: string, store: Store, snap: PracticeSnapshot, readPages: string[]): { title: string; terms: Term[] } | null {
  if (deck === "smart") return { title: "Smart deck", terms: weighted(store.glossary, snap, 20) };
  if (deck === "reading") return { title: "From your reading", terms: shuffled(fromReading(store, readPages)).slice(0, 20) };
  if (deck.startsWith("topic:")) {
    const category = deck.slice("topic:".length);
    const terms = store.glossary.filter((t) => t.category === category);
    return terms.length ? { title: category, terms: weighted(terms, snap, 20) } : null;
  }
  return null;
}

/** /flashcards: choose a deck; /flashcards?deck=smart|reading|topic:<category> plays it. */
export function FlashcardsPage() {
  const [params, setParams] = useSearchParams();
  const location = useLocation();
  const navigate = useNavigate();
  const deck = params.get("deck");
  if (deck) {
    const fromList = (location.state as { fromList?: boolean } | null)?.fromList;
    const close = () => (fromList ? navigate(-1) : setParams({}, { replace: true }));
    return <DeckSession key={deck} deck={deck} onClose={close} />;
  }
  return <DeckList onPick={(d) => setParams({ deck: d }, { state: { fromList: true } })} />;
}

/** The deck the "game" deep link plays (Smart deck). */
export function SmartDeck({ onClose }: { onClose: () => void }) {
  return <DeckSession deck="smart" onClose={onClose} />;
}

function DeckSession({ deck, onClose }: { deck: string; onClose: () => void }) {
  const store = useStore();
  const { snap } = usePractice();
  const { lib } = useLibrary();
  const [built] = useState(() => buildDeck(deck, store, snap, lib.readPages));
  if (!built || built.terms.length === 0) {
    return (
      <GameFrame title="Flashcards" tint="var(--accent)" onClose={onClose}>
        <div className="pr-over">
          <h2 className="title-l">No cards here</h2>
          <p className="muted pr-over-detail">This deck is empty. Pick another one.</p>
          <button className="btn" onClick={onClose}>Choose a deck</button>
        </div>
      </GameFrame>
    );
  }
  return <FlashcardSession title={built.title} initial={built.terms} onClose={onClose} />;
}

function DeckList({ onPick }: { onPick: (deck: string) => void }) {
  const store = useStore();
  const { snap } = usePractice();
  const { lib } = useLibrary();
  const back = useBack("/glossary");
  const categories = [...new Set(store.glossary.map((t) => t.category))].sort();
  const reading = fromReading(store, lib.readPages);

  return (
    <div className="narrow stack" style={{ ["--gap" as string]: "18px" }}>
      <button className="pr-back" onClick={back}><Icon name="left" size={16} />Back</button>
      <header className="stack" style={{ ["--gap" as string]: "4px" }}>
        <h1 className="title-xl">Flashcards</h1>
        <span className="small muted">Flip, swipe, remember. Missed words come back in your reviews.</span>
      </header>
      <div className="card pr-decks">
        <DeckRow title="Smart deck" subtitle="Words due for review, then new ones" icon="sparkles" tint="var(--accent)" onClick={() => onPick("smart")} />
        {reading.length >= 5 && (
          <DeckRow title="From your reading" subtitle={`${reading.length} words on pages you've read`} icon="book" tint={tintVar("violet")} onClick={() => onPick("reading")} />
        )}
      </div>
      <section className="stack" style={{ ["--gap" as string]: "8px" }}>
        <h2 className="eyebrow" style={{ paddingLeft: 4 }}>By topic</h2>
        <div className="card pr-decks">
          {categories.map((c) => {
            const terms = store.glossary.filter((t) => t.category === c);
            const mastered = terms.filter((t) => isMastered(snap, meaningId(t.id))).length;
            return (
              <DeckRow key={c} title={c} subtitle={`${terms.length} words · ${mastered} mastered`} icon="glossary" tint={categoryTint(c)} onClick={() => onPick(`topic:${c}`)} />
            );
          })}
        </div>
      </section>
    </div>
  );
}

function DeckRow({ title, subtitle, icon, tint, onClick }: { title: string; subtitle: string; icon: string; tint: string; onClick: () => void }) {
  return (
    <button className="pr-deck" style={tinted(tint)} onClick={onClick}>
      <span className="pr-deck-icon"><PIcon name={icon} size={19} /></span>
      <span className="stack" style={{ ["--gap" as string]: "2px", flex: 1, minWidth: 0, textAlign: "left" }}>
        <span className="serif pr-deck-title">{title}</span>
        <span className="tiny muted">{subtitle}</span>
      </span>
      <span className="pr-deck-play"><Icon name="play" size={16} /></span>
    </button>
  );
}

// ---------- session ----------

type Motion = "none" | "snap" | "fly";

function FlashcardSession({ title, initial, onClose }: { title: string; initial: Term[]; onClose: () => void }) {
  const practice = usePractice();
  const [deck, setDeck] = useState(initial);
  const [position, setPosition] = useState(0);
  const [flipped, setFlipped] = useState(false);
  const [drag, setDrag] = useState({ x: 0, y: 0 });
  const [motion, setMotion] = useState<Motion>("none");
  const [known, setKnown] = useState<Term[]>([]);
  const [missed, setMissed] = useState<Term[]>([]);
  const [requeued, setRequeued] = useState<Record<string, number>>({});
  const busy = useRef(false);
  const timer = useRef<number>();
  const pointer = useRef<{ id: number; x: number; y: number; lastX: number; lastT: number; vx: number; moved: boolean } | null>(null);
  const finished = position >= deck.length;

  useEffect(() => () => window.clearTimeout(timer.current), []);
  useEffect(() => { if (finished) practice.practiced(); }, [finished]); // eslint-disable-line react-hooks/exhaustive-deps

  const flip = () => { if (!busy.current && !finished) setFlipped((f) => !f); };

  const swipe = (knewIt: boolean) => {
    if (busy.current || finished) return;
    busy.current = true;
    const term = deck[position];
    practice.mark(meaningId(term.id), knewIt, 5);
    const wasMissed = missed.some((t) => t.id === term.id);
    if (knewIt) {
      if (!wasMissed && !known.some((t) => t.id === term.id)) setKnown((k) => [...k, term]);
    } else {
      if (!wasMissed) setMissed((m) => [...m, term]);
      // Missed cards come back at the end of the deck (twice at most).
      if ((requeued[term.id] ?? 0) < 2) {
        setRequeued((r) => ({ ...r, [term.id]: (r[term.id] ?? 0) + 1 }));
        setDeck((d) => [...d, term]);
      }
    }
    setMotion("fly");
    setDrag((d) => ({ x: knewIt ? 640 : -640, y: d.y + 40 }));
    timer.current = window.setTimeout(() => {
      setMotion("none");
      setFlipped(false);
      setDrag({ x: 0, y: 0 });
      setPosition((p) => p + 1);
      busy.current = false;
    }, 210);
  };

  const restartWithMissed = () => {
    setDeck(shuffled(missed));
    setKnown([]);
    setMissed([]);
    setRequeued({});
    setPosition(0);
    setFlipped(false);
  };

  const close = () => {
    if (position > 0) practice.practiced();
    onClose();
  };

  // Keyboard: ← again, → knew it, Space/Enter flip.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (typingIn(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (e.key === "ArrowRight") { e.preventDefault(); swipe(true); }
      else if (e.key === "ArrowLeft") { e.preventDefault(); swipe(false); }
      else if ((e.key === " " || e.key === "Enter") && !typingIn(e, true)) { e.preventDefault(); flip(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const onPointerDown = (e: ReactPointerEvent<HTMLDivElement>) => {
    if (busy.current || (e.pointerType === "mouse" && e.button !== 0)) return;
    pointer.current = { id: e.pointerId, x: e.clientX, y: e.clientY, lastX: e.clientX, lastT: performance.now(), vx: 0, moved: false };
    e.currentTarget.setPointerCapture(e.pointerId);
    setMotion("none");
  };
  const onPointerMove = (e: ReactPointerEvent<HTMLDivElement>) => {
    const p = pointer.current;
    if (!p || p.id !== e.pointerId) return;
    const now = performance.now();
    if (now > p.lastT) {
      p.vx = (e.clientX - p.lastX) / (now - p.lastT);
      p.lastX = e.clientX;
      p.lastT = now;
    }
    const dx = e.clientX - p.x, dy = e.clientY - p.y;
    if (Math.abs(dx) > 5 || Math.abs(dy) > 5) p.moved = true;
    if (p.moved) setDrag({ x: dx, y: dy });
  };
  const onPointerUp = (e: ReactPointerEvent<HTMLDivElement>) => {
    const p = pointer.current;
    if (!p || p.id !== e.pointerId) return;
    pointer.current = null;
    if (!p.moved) { flip(); return; }
    const dx = e.clientX - p.x;
    const predicted = dx + p.vx * 300;
    if (dx > 110 || predicted > 260) swipe(true);
    else if (dx < -110 || predicted < -260) swipe(false);
    else { setMotion("snap"); setDrag({ x: 0, y: 0 }); }
  };
  const onPointerCancel = () => {
    pointer.current = null;
    setMotion("snap");
    setDrag({ x: 0, y: 0 });
  };
  const onCardKey = (e: ReactKeyboardEvent<HTMLDivElement>) => {
    if (e.key === " " || e.key === "Enter") { e.preventDefault(); flip(); }
  };

  if (finished) {
    return (
      <GameFrame title={title} tint="var(--accent)" onClose={close}>
        <div className="pr-over">
          <span className="pr-over-icon" style={{ color: missed.length ? "var(--lime)" : "var(--amber)" }}>
            <PIcon name={missed.length ? "quiz" : "star"} size={64} />
          </span>
          <h2 className="title-xl" style={{ textAlign: "center" }}>{missed.length ? "Deck done" : "You knew them all!"}</h2>
          <p className="muted pr-over-detail">{known.length} known first time · {missed.length} to practise</p>
          {missed.length > 0 && (
            <div className="card pr-missed">
              <h3 className="pr-missed-title">Coming back in your reviews</h3>
              {missed.map((t) => (
                <Link key={t.id} to={`/glossary/${t.id}`} className="pr-missed-row" style={tinted(categoryTint(t.category))}>
                  <span className="serif pr-missed-name">{t.term}</span>
                  <span className="serif pr-missed-short">{t.short}</span>
                </Link>
              ))}
            </div>
          )}
          <div className="stack pr-over-actions" style={{ ["--gap" as string]: "10px" }}>
            {missed.length > 0 && (
              <button className="btn block" style={tinted("var(--coral)")} onClick={restartWithMissed} autoFocus>
                <PIcon name="refresh" />Go again with these {missed.length}
              </button>
            )}
            <button className={`btn block${missed.length ? " secondary" : ""}`} onClick={onClose} autoFocus={!missed.length}>Done</button>
          </div>
        </div>
      </GameFrame>
    );
  }

  const term = deck[position];
  const next = deck[position + 1];
  const transition = motion === "fly" ? "transform 0.22s ease-in" : motion === "snap" ? "transform 0.38s cubic-bezier(0.3, 1.45, 0.5, 1)" : "none";

  return (
    <GameFrame title={title} tint="var(--accent)" onClose={close}>
      <div className="pr-cards-top">
        <div className="progress"><div style={{ width: `${(position / Math.max(deck.length, 1)) * 100}%`, transition: "width 0.3s" }} /></div>
        <div className="row pr-counts">
          <span style={{ color: "var(--lime)" }}><PIcon name="check" size={14} />{known.length}</span>
          <span className="spacer" />
          <span className="muted">{Math.min(position + 1, deck.length)} of {deck.length}</span>
          <span className="spacer" />
          <span style={{ color: "var(--coral)" }}><PIcon name="refresh" size={14} />{missed.length}</span>
        </div>
      </div>

      <div className="pr-stack">
        {next && (
          <div className="pr-card pr-peek" aria-hidden="true">
            <div className="pr-flip"><Face term={next} back={false} /></div>
          </div>
        )}
        <div
          key={position}
          className="pr-card pr-current"
          role="button"
          tabIndex={0}
          aria-label={flipped ? `${term.term}: ${term.short}` : `${term.term}. Press to flip.`}
          style={{ transform: `translate(${drag.x}px, ${drag.y}px) rotate(${drag.x / 18}deg)`, transition }}
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onPointerCancel={onPointerCancel}
          onKeyDown={onCardKey}
        >
          <div className={`pr-flip${flipped ? " on" : ""}`}>
            <Face term={term} back={false} />
            <Face term={term} back />
          </div>
          <span className="pr-stamp know" style={{ opacity: Math.max(0, Math.min(1, drag.x / 120)) }}>Know it</span>
          <span className="pr-stamp again" style={{ opacity: Math.max(0, Math.min(1, -drag.x / 120)) }}>Again</span>
        </div>
      </div>

      <div className="pr-controls">
        <button className="pr-round" style={tinted("var(--coral)")} onClick={() => swipe(false)} aria-label="Again" title="Again (←)">
          <PIcon name="close" size={24} />
        </button>
        <button className="pr-round small" style={tinted("var(--ink-2)")} onClick={flip} aria-label="Flip" title="Flip (Space)">
          <PIcon name="flip" size={18} />
        </button>
        <button className="pr-round" style={tinted("var(--lime)")} onClick={() => swipe(true)} aria-label="I knew it" title="I knew it (→)">
          <PIcon name="check" size={24} />
        </button>
      </div>
      <p className="pr-hint">Space to flip · ← again · → knew it</p>
    </GameFrame>
  );
}

/** One side of a flashcard. */
function Face({ term, back }: { term: Term; back: boolean }) {
  const tint = categoryTint(term.category);
  return (
    <div className={`pr-face ${back ? "back" : "front"}`} style={tinted(tint)}>
      <div className="row">
        <Pill text={term.category} tint={tint} />
        <span className="spacer" />
        <span className="pr-face-glyph"><PIcon name={back ? "book" : "question"} /></span>
      </div>
      <div className="pr-face-body">
        {back ? (
          <>
            <span className="serif pr-back-term">{term.term}</span>
            <p className="serif pr-back-short">{term.short}</p>
            <p className="serif pr-back-def">{term.definition}</p>
          </>
        ) : (
          <>
            <h2 className="pr-front-term">{term.term}</h2>
            {term.aka.length > 0 && <p className="pr-front-aka">{term.aka.join(" · ")}</p>}
            <p className="pr-front-ask">Do you know what it means?</p>
          </>
        )}
      </div>
    </div>
  );
}
