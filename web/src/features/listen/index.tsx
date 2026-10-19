// Listen mode: narrated playback of a book (port of Listener.swift + ListenViews.swift).
import { createContext, useContext, useEffect, useMemo, useState, useSyncExternalStore, type ReactNode } from "react";
import { Link, useLocation } from "react-router-dom";
import { type Book, url, useStore } from "../../content";
import { useLocal } from "../../store";
import { Icon, tinted, tintVar } from "../../ui";
import { ListenEngine, type ListenState, SPEEDS } from "./engine";
import "./listen.css";

export interface ListenApi {
  /** Start narrating `book` from page `index`. */
  start: (book: Book, index: number) => void;
  /** True while a listening session exists (playing or paused). */
  isActive: boolean;
  isPlaying: boolean;
  /** Page id and panel index currently spoken (the reader highlights that panel). */
  pageId?: string;
  panel?: number;
  toggle: () => void;
  stop: () => void;
}

/** What the mini player needs on top of the public API. */
interface ListenInternal extends ListenApi {
  engine?: ListenEngine;
  state: ListenState;
  speed: number;
  setSpeed: (v: number) => void;
}

const noop: ListenInternal = {
  start: () => {}, isActive: false, isPlaying: false, toggle: () => {}, stop: () => {},
  state: { pageIndex: 0, panel: null, isPlaying: false, pageProgress: 0 }, speed: 1, setSpeed: () => {},
};
const Ctx = createContext<ListenInternal>(noop);
export const useListen = (): ListenApi => useContext(Ctx);

export function ListenProvider({ children }: { children: ReactNode }) {
  const [engine] = useState(() => new ListenEngine());
  const state = useSyncExternalStore(engine.subscribe, engine.getState, engine.getState);
  const [storedSpeed, setSpeed] = useLocal<number>("listen.speed", 1);
  const speed = SPEEDS.some((s) => Math.abs(s - storedSpeed) < 0.01) ? storedSpeed : 1;

  useEffect(() => engine.setSpeed(speed), [engine, speed]);
  useEffect(() => () => engine.stop(), [engine]);

  const value = useMemo<ListenInternal>(() => ({
    start: (book, index) => engine.start(book, index),
    isActive: !!state.book,
    isPlaying: state.isPlaying,
    pageId: state.book?.pages[state.pageIndex]?.id,
    panel: state.panel ?? undefined,
    toggle: engine.toggle,
    stop: engine.stop,
    engine,
    state,
    speed,
    setSpeed,
  }), [engine, state, speed, setSpeed]);

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

const speedLabel = (s: number) => `${s}×`;

/** Global mini player shown above the tab bar while a session is active. */
export function ListenBar() {
  const { engine, state, speed, setSpeed } = useContext(Ctx);
  const store = useStore();
  const location = useLocation();
  const [expanded, setExpanded] = useState(false);
  const book = state.book;
  const page = book?.pages[state.pageIndex];

  useEffect(() => { if (!book) setExpanded(false); }, [book]);
  useEffect(() => setExpanded(false), [location.pathname]);

  if (!engine || !book || !page) return null;

  const tint = tintVar(store.collectionFor(book)?.tint ?? "");
  const readerLink = `/read/${book.id}/${state.pageIndex}?mode=text`;
  const reading = location.pathname.startsWith("/read/");
  const nextSpeed = SPEEDS[(SPEEDS.findIndex((s) => Math.abs(s - speed) < 0.01) + 1) % SPEEDS.length];
  const atEnd = state.pageIndex + 1 >= book.pages.length;

  return (
    <div className={`listen-bar${reading ? " reading" : ""}`} style={tinted(tint)} role="region" aria-label="Listening">
      {expanded && (
        <div className="listen-panel card" role="dialog" aria-label="Listen controls">
          <div className="listen-panel-head">
            <img className="listen-panel-thumb" src={url(page.thumb)} alt="" />
            <div className="stack" style={{ ["--gap" as string]: "4px", minWidth: 0 }}>
              <span className="eyebrow">Listening</span>
              <strong className="serif listen-panel-title">{page.title}</strong>
              <span className="small muted">{book.title} · page {state.pageIndex + 1} of {book.pages.length}</span>
            </div>
            <button className="listen-icon" aria-label="Hide controls" onClick={() => setExpanded(false)}><Icon name="down" /></button>
          </div>

          <div className="listen-transport">
            <button className="listen-icon big" aria-label="Previous page" onClick={engine.previous}><Icon name="left" size={26} /></button>
            <button className="listen-play" aria-label={state.isPlaying ? "Pause" : "Play"} onClick={engine.toggle}>
              <Icon name={state.isPlaying ? "pause" : "play"} size={28} />
            </button>
            <button className="listen-icon big" aria-label="Next page" disabled={atEnd} onClick={engine.next}><Icon name="right" size={26} /></button>
          </div>

          <div className="listen-speeds" role="group" aria-label="Speed">
            {SPEEDS.map((s) => (
              <button key={s} className={`listen-speed${Math.abs(s - speed) < 0.01 ? " on" : ""}`} aria-pressed={Math.abs(s - speed) < 0.01} onClick={() => setSpeed(s)}>
                {speedLabel(s)}
              </button>
            ))}
          </div>

          <div className="row" style={{ ["--gap" as string]: "10px" }}>
            <Link to={readerLink} className="btn secondary" style={{ flex: 1 }}><Icon name="text" />Read along</Link>
            <button className="btn secondary" style={{ flex: 1, ...tinted(tintVar("coral")) }} onClick={engine.stop}>
              <Icon name="close" />Stop
            </button>
          </div>

          <div className="listen-pages">
            <span className="eyebrow">Pages</span>
            {book.pages.map((p, i) => (
              <button key={p.id} className={`listen-page${i === state.pageIndex ? " on" : ""}`} onClick={() => engine.jump(i)}>
                <span className="listen-page-num">{i + 1}</span>
                <span className="listen-page-title">{p.title}</span>
                {i === state.pageIndex && state.isPlaying && <span className="listen-wave" aria-hidden="true"><i /><i /><i /></span>}
              </button>
            ))}
          </div>
        </div>
      )}

      <div className="listen-mini">
        <button className="listen-thumb" aria-label={expanded ? "Hide listen controls" : "Show listen controls"} aria-expanded={expanded} onClick={() => setExpanded((e) => !e)}>
          <img src={url(page.thumb)} alt="" />
        </button>
        <Link to={readerLink} className="listen-title" aria-label={`Listening to ${page.title}. Open the page`}>
          <span className="serif listen-title-main">{page.title}</span>
          <span className="tiny muted listen-title-sub">{book.title} · {state.pageIndex + 1}/{book.pages.length}</span>
        </Link>
        <button className="listen-speed-chip" aria-label={`Speed ${speedLabel(speed)}. Change to ${speedLabel(nextSpeed)}`} onClick={() => setSpeed(nextSpeed)}>
          {speedLabel(speed)}
        </button>
        <button className="listen-icon tinted" aria-label={state.isPlaying ? "Pause" : "Play"} onClick={engine.toggle}>
          <Icon name={state.isPlaying ? "pause" : "play"} size={20} />
        </button>
        <button className="listen-icon" aria-label="Next page" disabled={atEnd} onClick={engine.next}>
          <Icon name="right" size={20} />
        </button>
        <button className="listen-icon" aria-label="Stop listening" onClick={engine.stop}>
          <Icon name="close" size={18} />
        </button>
        <div className="listen-progress" aria-hidden="true"><div style={{ width: `${state.pageProgress * 100}%` }} /></div>
      </div>
    </div>
  );
}
