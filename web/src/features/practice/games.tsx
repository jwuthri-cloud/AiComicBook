// Practice games (port of GamesView.swift): Match, Speed round and Zoom guess.
import { useEffect, useRef, useState } from "react";
import { useNavigate } from "react-router-dom";
import { type Page, type Term, url, useStore } from "../../content";
import { useReaderMode } from "../../store";
import { Pill, categoryTint, tintVar, tinted } from "../../ui";
import { meaningId, nameId, randomElement, shuffled, useBestMatch, useBestSpeed, useBestZoom, usePractice, weighted } from "./progress";
import { GameFrame, GameOver, PIcon, typingIn, useNow } from "./shared";

/** setTimeout that is cancelled when the component unmounts. */
function useLater() {
  const timers = useRef<number[]>([]);
  useEffect(() => () => timers.current.forEach((t) => window.clearTimeout(t)), []);
  return (ms: number, fn: () => void) => { timers.current.push(window.setTimeout(fn, ms)); };
}

// ---------- Match ----------

const MATCH_ROUNDS = 3;
const MATCH_PAIRS = 5;

/** Pair five words with their meanings, three rounds, against the clock. */
export function MatchGame({ onClose }: { onClose: () => void }) {
  const store = useStore();
  const practice = usePractice();
  const [best, setBest] = useBestMatch();
  const later = useLater();
  const tint = tintVar("teal");

  // One topic per round keeps the meanings close enough to make you think.
  const deal = () => {
    const byCategory = new Map<string, Term[]>();
    for (const t of store.glossary) byCategory.set(t.category, [...(byCategory.get(t.category) ?? []), t]);
    const pool = randomElement([...byCategory.values()].filter((v) => v.length >= MATCH_PAIRS)) ?? store.glossary;
    const chosen = weighted(pool, practice.snap, MATCH_PAIRS);
    return { terms: shuffled(chosen), definitions: shuffled(chosen) };
  };

  const [board, setBoard] = useState(deal);
  const [round, setRound] = useState(0);
  const [selectedTerm, setSelectedTerm] = useState<string | null>(null);
  const [selectedDef, setSelectedDef] = useState<string | null>(null);
  const [matched, setMatched] = useState<Set<string>>(() => new Set());
  const [wrongIds, setWrongIds] = useState<string[]>([]);
  const [mistakes, setMistakes] = useState(0);
  const slipped = useRef(new Set<string>());
  const [start, setStart] = useState(() => Date.now());
  const [finishedTime, setFinishedTime] = useState<number | null>(null);
  const [isRecord, setIsRecord] = useState(false);
  const now = useNow(finishedTime == null ? 100 : null);

  const newGame = () => {
    setRound(0);
    setMistakes(0);
    slipped.current = new Set();
    setFinishedTime(null);
    setIsRecord(false);
    setSelectedTerm(null);
    setSelectedDef(null);
    setMatched(new Set());
    setBoard(deal());
    setStart(Date.now());
  };

  const nextRound = () => {
    later(450, () => {
      if (round + 1 < MATCH_ROUNDS) {
        setRound(round + 1);
        setMatched(new Set());
        setBoard(deal());
      } else {
        const time = (Date.now() - start) / 1000 + mistakes * 3;
        const record = best === 0 || time < best;
        setIsRecord(record);
        if (record) setBest(time);
        practice.award(Math.max(10, 60 - mistakes * 5));
        practice.practiced();
        setFinishedTime(time);
      }
    });
  };

  const select = (kind: "term" | "def", id: string) => {
    let t = selectedTerm, d = selectedDef;
    if (kind === "term") t = t === id ? null : id;
    else d = d === id ? null : id;
    if (!t || !d) {
      setSelectedTerm(t);
      setSelectedDef(d);
      return;
    }
    setSelectedTerm(null);
    setSelectedDef(null);
    if (t === d) {
      const next = new Set(matched).add(t);
      setMatched(next);
      practice.mark(nameId(t), !slipped.current.has(t), 5);
      if (board.terms.every((x) => next.has(x.id))) nextRound();
    } else {
      setMistakes((m) => m + 1);
      slipped.current.add(t);
      setWrongIds([t, d]);
      later(400, () => setWrongIds([]));
    }
  };

  if (finishedTime != null) {
    return (
      <GameFrame title="Match" tint={tint} onClose={onClose}>
        <GameOver
          icon="grid"
          headline={`${finishedTime.toFixed(1)} s`}
          detail={`${MATCH_ROUNDS * MATCH_PAIRS} pairs · ${mistakes} ${mistakes === 1 ? "slip" : "slips"} (+3 s each)`}
          isRecord={isRecord}
          again={newGame}
          done={onClose}
        />
      </GameFrame>
    );
  }

  const elapsed = Math.max(0, (now - start) / 1000) + mistakes * 3;
  const tile = (text: string, id: string, kind: "term" | "def") => {
    const done = matched.has(id);
    const wrong = (kind === "term" ? wrongIds[0] : wrongIds[1]) === id;
    const selected = (kind === "term" ? selectedTerm : selectedDef) === id;
    return (
      <button
        key={id}
        className={`pr-tile ${kind}${done ? " done" : ""}${wrong ? " wrong" : ""}${selected ? " selected" : ""}`}
        disabled={done}
        aria-pressed={selected}
        onClick={() => select(kind, id)}
      >
        <span>{text}</span>
      </button>
    );
  };

  return (
    <GameFrame title="Match" tint={tint} onClose={onClose} right={<span className="pr-timer">{elapsed.toFixed(1)} s</span>}>
      <div className="row pr-sub">
        <span>Round {round + 1} of {MATCH_ROUNDS}</span>
        <span className="spacer" />
        {best > 0 && <span>Best {best.toFixed(1)} s</span>}
      </div>
      <div className="pr-match">
        <div className="pr-col" aria-label="Words">{board.terms.map((t) => tile(t.term, t.id, "term"))}</div>
        <div className="pr-col" aria-label="Meanings">{board.definitions.map((t) => tile(t.short, t.id, "def"))}</div>
      </div>
      <p className="pr-hint always">Pick a word, then its meaning.</p>
    </GameFrame>
  );
}

// ---------- Speed round ----------

const SPEED_SECONDS = 60;
const multiplierFor = (streak: number) => Math.min(4, 1 + Math.floor(streak / 3));

/** 60 seconds: is this the right meaning? Streaks multiply the score. */
export function SpeedRound({ onClose }: { onClose: () => void }) {
  const store = useStore();
  const practice = usePractice();
  const [best, setBest] = useBestSpeed();
  const later = useLater();
  const tint = tintVar("amber");

  const [phase, setPhase] = useState<"intro" | "playing" | "over">("intro");
  const [card, setCard] = useState<{ term: Term; shown: Term; n: number } | null>(null);
  const [score, setScore] = useState(0);
  const [streak, setStreak] = useState(0);
  const [answered, setAnswered] = useState(0);
  const [correctCount, setCorrectCount] = useState(0);
  const [start, setStart] = useState<number | null>(null);
  const [flash, setFlash] = useState<boolean | null>(null);
  const [isRecord, setIsRecord] = useState(false);
  const locked = useRef(false);
  // Latch, not state: finish() writes to localStorage, whose sync re-renders still see phase "playing".
  const ended = useRef(true);
  const now = useNow(phase === "playing" ? 100 : null);
  const left = start == null ? SPEED_SECONDS : Math.max(0, SPEED_SECONDS - (now - start) / 1000);

  const deal = () => {
    const next = randomElement(store.glossary);
    if (!next) return;
    let shown = next;
    if (Math.random() < 0.5) {
      const siblings = store.glossary.filter((t) => t.category === next.category && t.id !== next.id && t.short !== next.short);
      shown = randomElement(siblings) ?? store.glossary.find((t) => t.id !== next.id) ?? next;
    }
    setCard((c) => ({ term: next, shown, n: (c?.n ?? 0) + 1 }));
    setFlash(null);
  };

  const begin = () => {
    setScore(0);
    setStreak(0);
    setAnswered(0);
    setCorrectCount(0);
    setIsRecord(false);
    locked.current = false;
    ended.current = false;
    setStart(Date.now());
    setPhase("playing");
    deal();
  };

  const finish = () => {
    if (ended.current) return;
    ended.current = true;
    const record = score > best;
    setIsRecord(record);
    if (record) setBest(score);
    practice.award(Math.floor(score / 5));
    practice.practiced();
    setPhase("over");
  };

  useEffect(() => { if (phase === "playing" && left <= 0) finish(); }); // eslint-disable-line react-hooks/exhaustive-deps

  const answer = (saysRight: boolean) => {
    if (phase !== "playing" || ended.current || !card || locked.current || left <= 0) return;
    const isRight = (card.term.id === card.shown.id) === saysRight;
    setAnswered((a) => a + 1);
    if (isRight) {
      const s = streak + 1;
      setCorrectCount((c) => c + 1);
      setStreak(s);
      setScore((sc) => sc + 10 * multiplierFor(s));
    } else {
      setStreak(0);
      practice.mark(meaningId(card.term.id), false);
    }
    setFlash(isRight);
    locked.current = true;
    later(180, () => {
      locked.current = false;
      if (!ended.current) deal();
    });
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (typingIn(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      if (phase === "playing") {
        if (e.key === "ArrowLeft") { e.preventDefault(); answer(false); }
        else if (e.key === "ArrowRight") { e.preventDefault(); answer(true); }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  let body;
  if (phase === "over") {
    body = (
      <GameOver
        icon="bolt"
        headline={`${score} points`}
        detail={`${correctCount} of ${answered} right` + (answered > 0 ? ` · ${Math.floor((correctCount / answered) * 100)}%` : "")}
        isRecord={isRecord}
        again={begin}
        done={onClose}
      />
    );
  } else if (phase === "intro") {
    body = (
      <div className="pr-over">
        <span className="pr-over-icon"><PIcon name="bolt" size={72} /></span>
        <h2 className="title-xl">60 seconds</h2>
        <p className="serif muted pr-over-detail" style={{ fontSize: 18, lineHeight: 1.5 }}>
          A word and a meaning appear. Is it the right meaning? Answer as many as you can — streaks multiply your points.
        </p>
        {best > 0 && <Pill text={`Best: ${best}`} tint={tint} icon={<PIcon name="trophy" size={14} />} />}
        <div className="pr-over-actions">
          <button className="btn block" onClick={begin} autoFocus><PIcon name="play" />Start</button>
        </div>
      </div>
    );
  } else {
    const multiplier = multiplierFor(streak);
    body = (
      <div className="stack pr-speed" style={{ ["--gap" as string]: "18px" }}>
        <div className="stack" style={{ ["--gap" as string]: "6px" }}>
          <div className="progress pr-timebar" style={tinted(left < 10 ? "var(--coral)" : tint)}>
            <div style={{ width: `${(left / SPEED_SECONDS) * 100}%` }} />
          </div>
          <div className="row pr-sub">
            <span className="pr-num">{Math.ceil(left)} s</span>
            <span className="spacer" />
            {streak >= 3 && <span style={{ color: tint }}>×{multiplier} streak</span>}
            <span className="spacer" />
            <span className="pr-num">{score} pts</span>
          </div>
        </div>
        {card && (
          <div key={card.n} className={`pr-speed-card${flash === true ? " good" : flash === false ? " bad" : ""}`} aria-live="polite">
            <span><Pill text={card.term.category} tint={categoryTint(card.term.category)} /></span>
            <h2 className="pr-speed-term">{card.term.term}</h2>
            <span className="small faint">means…</span>
            <p className="serif pr-speed-short">{card.shown.short}</p>
          </div>
        )}
        <div className="pr-answers">
          <button className="pr-answer" style={tinted("var(--coral)")} onClick={() => answer(false)}><PIcon name="close" size={22} />Wrong</button>
          <button className="pr-answer" style={tinted("var(--lime)")} onClick={() => answer(true)}><PIcon name="check" size={22} />Right</button>
        </div>
        <p className="pr-hint">← wrong · → right</p>
      </div>
    );
  }

  return <GameFrame title="Speed round" tint={tint} onClose={onClose}>{body}</GameFrame>;
}

// ---------- Zoom guess ----------

const ZOOM_ROUNDS = 8;
const ZOOMS = [3.4, 2.2, 1.35, 1];

interface ZoomDeal { page: Page; options: Page[]; anchor: { x: number; y: number } }

/** A zoomed-in detail of a comic page: which page is it? Each wrong guess zooms out (3, 2, then 1 point). */
export function ZoomGuess({ onClose }: { onClose: () => void }) {
  const store = useStore();
  const practice = usePractice();
  const navigate = useNavigate();
  const [, setReaderMode] = useReaderMode();
  const [best, setBest] = useBestZoom();
  const tint = tintVar("violet");

  // Pages with real pictures (not cover-like title pages), answers from the same collection.
  const deal = (): ZoomDeal | null => {
    const pool = store.allBooks.flatMap((b) => b.pages).filter((p) => p.panels.length > 0);
    const pick = randomElement(pool);
    const book = pick && store.bookFor(pick);
    if (!pick || !book) return null;
    const collection = store.collectionFor(book);
    const siblings = collection ? collection.books.flatMap((b) => b.pages) : book.pages;
    const titles = new Set([pick.title]);
    const distractors: Page[] = [];
    for (const p of shuffled(siblings)) {
      if (distractors.length === 3) break;
      if (p.id === pick.id || titles.has(p.title)) continue;
      titles.add(p.title);
      distractors.push(p);
    }
    // Away from the top, where the page title is printed.
    return { page: pick, options: shuffled([pick, ...distractors]), anchor: { x: 0.2 + Math.random() * 0.6, y: 0.38 + Math.random() * 0.47 } };
  };

  const [round, setRound] = useState(0);
  const [current, setCurrent] = useState(deal);
  const [eliminated, setEliminated] = useState<Set<string>>(() => new Set());
  const [level, setLevel] = useState(0);
  const [solved, setSolved] = useState(false);
  const [score, setScore] = useState(0);
  const [over, setOver] = useState(false);
  const [isRecord, setIsRecord] = useState(false);

  const nextDeal = () => {
    setCurrent(deal());
    setEliminated(new Set());
    setLevel(0);
    setSolved(false);
  };

  const newGame = () => {
    setRound(0);
    setScore(0);
    setOver(false);
    setIsRecord(false);
    nextDeal();
  };

  const guess = (option: Page) => {
    if (!current || solved || eliminated.has(option.id)) return;
    if (option.id === current.page.id) {
      setScore((s) => s + Math.max(1, 3 - level));
      setSolved(true);
    } else {
      const next = new Set(eliminated).add(option.id);
      setEliminated(next);
      setLevel((l) => l + 1);
      if (next.size >= current.options.length - 1) setSolved(true);
    }
  };

  const nextRound = () => {
    if (round + 1 < ZOOM_ROUNDS) {
      setRound(round + 1);
      nextDeal();
    } else {
      const record = score > best;
      setIsRecord(record);
      if (record) setBest(score);
      practice.award(score * 3);
      practice.practiced();
      setOver(true);
    }
  };

  const read = (page: Page) => {
    const book = store.bookFor(page);
    const index = Math.max(0, book?.pages.findIndex((p) => p.id === page.id) ?? 0);
    setReaderMode("comic");
    navigate(`/read/${page.bookId}/${index}`);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (over || !current || typingIn(e) || e.metaKey || e.ctrlKey || e.altKey) return;
      const n = Number(e.key);
      if (!solved && Number.isInteger(n) && n >= 1 && n <= current.options.length) { e.preventDefault(); guess(current.options[n - 1]); }
      else if (solved && e.key === "Enter" && !typingIn(e, true)) { e.preventDefault(); nextRound(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });

  const right = <span className="pr-timer" style={{ color: tint }}>{score} pts</span>;

  if (over) {
    return (
      <GameFrame title="Zoom guess" tint={tint} onClose={onClose} right={right}>
        <GameOver
          icon="zoom"
          headline={`${score} of ${ZOOM_ROUNDS * 3}`}
          detail={score >= ZOOM_ROUNDS * 2 ? "Sharp eyes!" : "Every guess teaches you the pages a little better."}
          isRecord={isRecord}
          again={newGame}
          done={onClose}
        />
      </GameFrame>
    );
  }
  if (!current) {
    return (
      <GameFrame title="Zoom guess" tint={tint} onClose={onClose}>
        <p className="muted">No pages to play with yet.</p>
      </GameFrame>
    );
  }

  const { page, options, anchor } = current;
  const worth = Math.max(1, 3 - level);
  const zoom = solved ? 1 : ZOOMS[Math.min(level, ZOOMS.length - 1)];

  return (
    <GameFrame title="Zoom guess" tint={tint} onClose={onClose} right={right}>
      <div className="stack" style={{ ["--gap" as string]: "14px" }}>
        <div className="row pr-sub">
          <span>Round {round + 1} of {ZOOM_ROUNDS}</span>
          <span className="spacer" />
          {!solved && <span>Worth {worth} {worth === 1 ? "point" : "points"}</span>}
        </div>
        <div className="pr-zoom-frame">
          <img
            key={page.id}
            src={url(page.image)}
            alt={solved ? page.title : "A zoomed-in detail of a comic page"}
            draggable={false}
            style={{ transform: `scale(${zoom})`, transformOrigin: `${anchor.x * 100}% ${anchor.y * 100}%` }}
          />
        </div>
        <p className="tiny faint" style={{ textAlign: "center", fontWeight: 600 }}>
          {solved ? store.bookFor(page)?.title : "Which page is this detail from?"}
        </p>
        <div className="stack" style={{ ["--gap" as string]: "8px" }}>
          {options.map((option, i) => {
            const isAnswer = option.id === page.id;
            const gone = eliminated.has(option.id);
            return (
              <button
                key={option.id}
                className={`pr-option${gone ? " gone" : ""}${solved && isAnswer ? " answer" : ""}`}
                disabled={gone || solved}
                onClick={() => guess(option)}
              >
                <kbd className="pr-kbd">{i + 1}</kbd>
                <span className="serif pr-option-title">{option.title}</span>
                {solved && isAnswer && <span style={{ color: "var(--lime)" }}><PIcon name="check" /></span>}
                {gone && <span style={{ color: "var(--coral)" }}><PIcon name="close" /></span>}
              </button>
            );
          })}
        </div>
        {solved && (
          <div className="pr-zoom-actions">
            <button className="btn secondary" onClick={() => read(page)}><PIcon name="book" />Read it</button>
            <button className="btn" onClick={nextRound} autoFocus><PIcon name="right" />{round + 1 < ZOOM_ROUNDS ? "Next" : "Finish"}</button>
          </div>
        )}
      </div>
    </GameFrame>
  );
}
