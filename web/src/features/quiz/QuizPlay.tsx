// Port of QuizSessionView.swift: one question at a time, explanation after answering, then a summary.
import { useCallback, useEffect, useRef, useState } from "react";
import { Link, useLocation, useNavigate, useSearchParams } from "react-router-dom";
import { type Store, useStore } from "../../content";
import { useAdvanced } from "../../store";
import { Icon, Pill, tinted, tintVar } from "../../ui";
import { buildSession, parseKind, quizPath, type QuizItem, type QuizSession } from "./engine";
import { QIcon } from "./icons";
import { StatTile } from "./parts";
import { useQuizState } from "./state";
import "./quiz.css";

interface Run {
  session: QuizSession;
  index: number;
  chosen: number | null;
  results: Record<string, boolean>;
  finished: boolean;
}

// The live session survives a trip to the reader and back (same history entry) or a reload.
const LIVE_KEY = "quiz.live";

function restore(key: string, search: string): Run | null {
  try {
    const saved = JSON.parse(sessionStorage.getItem(LIVE_KEY) ?? "null");
    const run = saved?.run as Run | undefined;
    if (saved?.key === key && saved.search === search && run && Array.isArray(run.session?.items)
      && (run.finished || run.index < run.session.items.length)) return run;
  } catch { /* ignore */ }
  return null;
}

function persist(key: string, search: string, run: Run) {
  try { sessionStorage.setItem(LIVE_KEY, JSON.stringify({ key, search, run })); } catch { /* ignore */ }
}

/** /read/<book>/<index>?mode=text for a page id. */
function readPath(store: Store, pageId?: string): string | undefined {
  const page = pageId ? store.pages.get(pageId) : undefined;
  const book = page ? store.books.get(page.bookId) : undefined;
  if (!page || !book) return undefined;
  return `/read/${book.id}/${Math.max(0, book.pages.findIndex((p) => p.id === page.id))}?mode=text`;
}

const GOOD = tintVar("lime");
const BAD = tintVar("coral");

export function QuizPlay() {
  const location = useLocation();
  return <QuizRun key={`${location.key}${location.search}`} />;
}

function QuizRun() {
  const store = useStore();
  const quiz = useQuizState();
  const location = useLocation();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const [run, setRun] = useState<Run>(() => restore(location.key, location.search) ?? {
    session: buildSession(store, quiz.snapshot, parseKind(params)),
    index: 0, chosen: null, results: {}, finished: false,
  });

  useEffect(() => persist(location.key, location.search, run), [run, location.key, location.search]);

  const { session, index, chosen, finished } = run;
  const item: QuizItem | undefined = session.items[index];
  const answering = useRef<string | null>(null);

  const close = useCallback(() => {
    if (location.key !== "default") navigate(-1);
    else navigate("/quiz");
  }, [location.key, navigate]);

  const choose = useCallback((i: number) => {
    if (!item || chosen !== null || answering.current === item.id) return;
    answering.current = item.id;
    const right = i === item.correct;
    quiz.answer(item, right);
    setRun((r) => ({ ...r, chosen: i, results: { ...r.results, [item.id]: right } }));
  }, [item, chosen, quiz]);

  const next = useCallback(() => {
    if (chosen === null) return;
    if (index >= session.items.length - 1) {
      quiz.finish(session.kind);
      setRun((r) => ({ ...r, finished: true }));
    } else {
      setRun((r) => ({ ...r, index: r.index + 1, chosen: null }));
    }
  }, [chosen, index, session, quiz]);

  const retryMissed = useCallback(() => {
    const missed = session.items.filter((i) => run.results[i.id] === false).map((i) => i.id);
    navigate(quizPath({ mode: "retry", ids: missed }), { replace: true });
  }, [session, run.results, navigate]);

  // Keyboard: 1–4 (or A–D, T/F) answer, Enter goes on.
  useEffect(() => {
    if (finished || !item) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const target = e.target as HTMLElement | null;
      if (target && (target.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(target.tagName))) return;
      const key = e.key.toLowerCase();
      let pick = -1;
      if (/^[1-9]$/.test(key)) pick = Number(key) - 1;
      else if (item.options.length === 2 && (key === "t" || key === "f")) pick = key === "t" ? 0 : 1;
      else if (item.options.length > 2 && /^[a-d]$/.test(key)) pick = key.charCodeAt(0) - 97;
      if (pick >= 0 && pick < item.options.length) {
        e.preventDefault();
        choose(pick);
      } else if (key === "enter" && chosen !== null && !e.repeat) {
        if (target?.closest("button, a")) return; // the focused control handles Enter itself
        e.preventDefault();
        next();
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [finished, item, chosen, choose, next]);

  if (!session.items.length) {
    return (
      <div className="narrow qz-session">
        <div className="card pad qz-empty">
          <QIcon name="book" size={34} />
          <h1 className="title-m">No questions here yet</h1>
          <p className="muted">
            {session.kind.mode === "review" ? "Nothing is due for review. Missed questions come back here." : "Read a few pages first, then come back."}
          </p>
          <Link to="/quiz" className="btn secondary">Back to Quiz</Link>
        </div>
      </div>
    );
  }

  if (finished) return <Summary run={run} onRetry={retryMissed} onDone={close} />;
  if (!item) return null;

  return (
    <QuestionView
      key={item.id}
      run={run}
      item={item}
      onChoose={choose}
      onNext={next}
      onClose={close}
      first={index === 0}
    />
  );
}

function QuestionView({ run, item, onChoose, onNext, onClose, first }: {
  run: Run; item: QuizItem; onChoose: (i: number) => void; onNext: () => void; onClose: () => void; first: boolean;
}) {
  const store = useStore();
  const [advanced] = useAdvanced();
  const { session, index, chosen, results } = run;
  const total = session.items.length;
  const promptRef = useRef<HTMLHeadingElement>(null);
  const nextRef = useRef<HTMLButtonElement>(null);
  const feedbackRef = useRef<HTMLDivElement>(null);

  // New question: back to the top, focus on the prompt (not on the very first one, to keep the page calm).
  useEffect(() => {
    window.scrollTo({ top: 0 });
    if (!first) promptRef.current?.focus({ preventScroll: true });
  }, [first]);

  // Answered: show the explanation and make Enter continue.
  useEffect(() => {
    if (chosen === null) return;
    nextRef.current?.focus({ preventScroll: true });
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    feedbackRef.current?.scrollIntoView({ block: "nearest", behavior: reduce ? "auto" : "smooth" });
  }, [chosen]);

  const page = item.pageId ? store.pages.get(item.pageId) : undefined;
  const book = page ? store.books.get(page.bookId) : undefined;
  const collection = book ? store.collectionFor(book) : undefined;
  const term = item.termId ? store.terms.get(item.termId) : undefined;
  const read = readPath(store, item.pageId);
  // Advanced mode adds the deeper note: the term's own for word questions, the page's otherwise.
  const further = advanced ? (term?.advanced || page?.deeper?.further) : undefined;
  const right = chosen !== null && chosen === item.correct;
  const isLast = index === total - 1;

  const optionState = (i: number): OptionState => {
    if (chosen === null) return "idle";
    if (i === item.correct) return "correct";
    if (i === chosen) return "wrong";
    return "dimmed";
  };

  return (
    <div className="narrow qz-session">
      <header className="qz-bar">
        <button type="button" className="iconbtn" aria-label="End quiz" onClick={onClose}><Icon name="close" size={17} /></button>
        <div className="qz-segments" role="progressbar" aria-label="Progress" aria-valuemin={1} aria-valuemax={total} aria-valuenow={index + 1}>
          {session.items.map((it, i) => {
            const r = results[it.id];
            const cls = r === true ? "good" : r === false ? "bad" : i === index ? "current" : "";
            return <span key={`${it.id}-${i}`} className={`qz-seg ${cls}`} />;
          })}
        </div>
        <span className="qz-count">{index + 1}/{total}</span>
      </header>

      <article className="qz-question stack" style={{ ["--gap" as string]: "20px" }}>
        <div className="stack" style={{ ["--gap" as string]: "10px" }}>
          <span className="eyebrow qz-ellipsis">{session.title}</span>
          <div className="row qz-meta">
            {item.termId ? (
              <Pill text="Word" tint={tintVar("teal")} icon={<QIcon name="word" size={14} />} />
            ) : page ? (
              <span className="pill qz-pagepill" style={tinted(tintVar(collection?.tint ?? ""))} title={page.title}>
                <QIcon name="book" size={14} />
                <span className="qz-ellipsis">{page.title}</span>
              </span>
            ) : null}
            <span className="spacer" />
            <span className="qz-dots" role="img" aria-label={`Difficulty ${item.difficulty} of 3`}>
              {[1, 2, 3].map((d) => <span key={d} className={d <= item.difficulty ? "on" : ""} />)}
            </span>
          </div>
        </div>

        <h2 ref={promptRef} tabIndex={-1} className="qz-prompt">{item.prompt}</h2>

        <div className="qz-options" role="group" aria-label="Answers">
          {item.options.map((text, i) => (
            <OptionButton
              key={i}
              letter={item.options.length === 2 ? (text === "True" ? "T" : text === "False" ? "F" : String.fromCharCode(65 + i)) : String.fromCharCode(65 + i)}
              shortcut={i + 1}
              text={text}
              state={optionState(i)}
              onClick={() => onChoose(i)}
            />
          ))}
        </div>

        <div aria-live="polite">
          {chosen !== null && (
            <div ref={feedbackRef} className="qz-feedback" style={tinted(right ? GOOD : BAD)}>
              <span className="qz-feedback-label">
                <QIcon name={right ? "checkCircle" : "bulb"} size={19} />
                {right ? "Correct" : "Not quite"}
              </span>
              {item.explanation && <p className="qz-explanation">{item.explanation}</p>}
              {further && <p className="qz-further">{further}</p>}
              {read && page && (
                <Link to={read} className="qz-readlink">
                  <QIcon name="book" size={16} />Read “{page.title}”
                </Link>
              )}
            </div>
          )}
        </div>
      </article>

      <div className="qz-footer">
        <button ref={nextRef} type="button" className="btn block" disabled={chosen === null} onClick={onNext}>
          {isLast ? "See results" : "Next question"}
        </button>
        <span className="qz-hint">1–{item.options.length} to answer · Enter for next</span>
      </div>
    </div>
  );
}

type OptionState = "idle" | "correct" | "wrong" | "dimmed";

function OptionButton({ letter, shortcut, text, state, onClick }: { letter: string; shortcut: number; text: string; state: OptionState; onClick: () => void }) {
  const suffix = state === "correct" ? ", correct answer" : state === "wrong" ? ", your answer, wrong" : "";
  return (
    <button
      type="button"
      className={`qz-option ${state}`}
      disabled={state !== "idle"}
      onClick={onClick}
      aria-label={text + suffix}
      aria-keyshortcuts={String(shortcut)}
    >
      <span className="qz-badge" aria-hidden="true">
        {state === "correct" ? <Icon name="check" size={16} /> : state === "wrong" ? <Icon name="close" size={15} /> : letter}
      </span>
      <span className="qz-option-text">{text}</span>
    </button>
  );
}

function verdict(score: number) {
  if (score >= 1) return "Perfect";
  if (score >= 0.8) return "Great work";
  if (score >= 0.5) return "Getting there";
  return "Keep reading";
}

/** Port of QuizSummaryView: score ring, streak and points, what to revisit, retry the misses. */
function Summary({ run, onRetry, onDone }: { run: Run; onRetry: () => void; onDone: () => void }) {
  const store = useStore();
  const quiz = useQuizState();
  const { session, results } = run;
  const total = session.items.length;
  const correct = session.items.filter((i) => results[i.id] === true).length;
  const score = total ? correct / total : 0;
  const tint = score >= 0.8 ? GOOD : score >= 0.5 ? tintVar("amber") : BAD;
  const missed = session.items.filter((i) => results[i.id] === false);
  const [shown, setShown] = useState(0);
  const headingRef = useRef<HTMLHeadingElement>(null);

  useEffect(() => {
    window.scrollTo({ top: 0 });
    headingRef.current?.focus({ preventScroll: true });
    const t = window.setTimeout(() => setShown(Math.max(score, 0.001)), 150);
    return () => window.clearTimeout(t);
  }, [score]);

  const size = 190;
  const stroke = 14;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;

  return (
    <div className="narrow qz-session qz-summary stack" style={{ ["--gap" as string]: "24px" }}>
      <div className="qz-score" style={tinted(tint)}>
        <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
          <circle cx={size / 2} cy={size / 2} r={r} className="qz-ring-track" strokeWidth={stroke} />
          <circle
            cx={size / 2} cy={size / 2} r={r} className="qz-ring-fill qz-score-fill" strokeWidth={stroke}
            strokeDasharray={c} strokeDashoffset={c * (1 - shown)} transform={`rotate(-90 ${size / 2} ${size / 2})`}
          />
        </svg>
        <div className="qz-score-text">
          <h1 ref={headingRef} tabIndex={-1} className="qz-score-value" aria-label={`${correct} of ${total} correct`}>{correct}/{total}</h1>
          <span className="qz-score-verdict">{verdict(score)}</span>
        </div>
      </div>
      <p className="qz-summary-title muted">{session.title}</p>

      <div className="qz-stats two">
        <StatTile value={String(quiz.streak)} label="day streak" icon="flame" tint={tintVar("coral")} />
        <StatTile value={String(quiz.xp)} label="points" icon="star" tint={tintVar("amber")} />
      </div>

      {missed.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "12px" }}>
          <h2 className="title-m" style={{ fontWeight: 700 }}>To revisit</h2>
          {missed.map((item) => {
            const read = readPath(store, item.pageId);
            const body = (
              <>
                <span className="qz-miss-icon"><QIcon name="xCircle" size={20} /></span>
                <span className="qz-row-text">
                  <span className="qz-miss-prompt">{item.prompt}</span>
                  <span className="qz-miss-answer">Answer: {item.options[item.correct]}</span>
                </span>
                {read && <span className="faint"><QIcon name="book" size={18} /></span>}
              </>
            );
            return read ? (
              <Link key={item.id} to={read} className="card qz-miss">{body}</Link>
            ) : (
              <div key={item.id} className="card qz-miss">{body}</div>
            );
          })}
        </section>
      )}

      <div className="stack" style={{ ["--gap" as string]: "12px" }}>
        {missed.length > 0 && (
          <button type="button" className="btn block" onClick={onRetry}>
            <Icon name="refresh" size={18} />Retry the {missed.length} I missed
          </button>
        )}
        <button type="button" className="btn secondary block" onClick={onDone}>Done</button>
      </div>
    </div>
  );
}
