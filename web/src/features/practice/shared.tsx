// Building blocks shared by the flashcards and the games: icons, the game frame and the end-of-game card.
import { useEffect, useState, type ReactNode } from "react";
import { useNavigate } from "react-router-dom";
import { Icon, tinted } from "../../ui";

const EXTRA: Record<string, ReactNode> = {
  trophy: <><path d="M8 4h8v5a4 4 0 0 1-8 0z" /><path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4" /><path d="M12 13v4M8 20h8M9.5 17h5" /></>,
  bolt: <path d="M13 3 5 13h6l-1 8 8-10h-6z" fill="currentColor" />,
  star: <path d="m12 3 2.7 5.6 6.1.8-4.5 4.2 1.1 6.1L12 16.8l-5.4 2.9 1.1-6.1-4.5-4.2 6.1-.8z" fill="currentColor" />,
  grid: <><rect x="4" y="4" width="7" height="7" rx="1.5" /><rect x="13" y="4" width="7" height="7" rx="1.5" /><rect x="4" y="13" width="7" height="7" rx="1.5" /><rect x="13" y="13" width="7" height="7" rx="1.5" /></>,
  zoom: <><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5M11 8v6M8 11h6" /></>,
  question: <><circle cx="12" cy="12" r="9" /><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6V14M12 17h.01" /></>,
  book: <><path d="M4 5a2 2 0 0 1 2-2h13v16H6a2 2 0 0 0-2 2z" /><path d="M4 19V5M8 7h7" /></>,
  flip: <><path d="M4 12a8 8 0 0 1 13.7-5.7L20 8.5" /><path d="M20 3.5v5h-5" /><path d="M20 12a8 8 0 0 1-13.7 5.7L4 15.5" /><path d="M4 20.5v-5h5" /></>,
};

export function PIcon({ name, size = 18 }: { name: string; size?: number }) {
  const p = EXTRA[name];
  if (!p) return <Icon name={name} size={size} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {p}
    </svg>
  );
}

/** Pops history when the app pushed this page, else goes to `fallback`. */
export function useBack(fallback: string) {
  const navigate = useNavigate();
  return () => {
    const idx = (window.history.state as { idx?: number } | null)?.idx ?? 0;
    if (idx > 0) navigate(-1);
    else navigate(fallback, { replace: true });
  };
}

/** True when keyboard shortcuts should be ignored because the user is typing or pressing a control. */
export function typingIn(e: KeyboardEvent, alsoControls = false): boolean {
  const el = e.target as HTMLElement | null;
  if (!el?.closest) return false;
  if (el.closest("input, textarea, select, [contenteditable=true]")) return true;
  return alsoControls && !!el.closest("button, a, [role=button]");
}

/** Re-renders every `interval` ms while running and returns the current time. */
export function useNow(interval: number | null): number {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (interval == null) return;
    setNow(Date.now());
    const id = window.setInterval(() => setNow(Date.now()), interval);
    return () => window.clearInterval(id);
  }, [interval]);
  return now;
}

/** Full-width game frame: Close, centred title, a status slot on the right. Escape closes. */
export function GameFrame({ title, tint, onClose, right, children }: { title: string; tint: string; onClose: () => void; right?: ReactNode; children: ReactNode }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === "Escape" && !typingIn(e)) onClose(); };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [onClose]);
  // The outer box spans the page gutters and clips sideways, so a card swiped off-screen never adds a scrollbar.
  return (
    <div className="pr-wrap">
      <div className="pr-game" style={tinted(tint)}>
        <header className="pr-bar">
          <button className="pr-close" onClick={onClose}>Close</button>
          <h1 className="pr-title">{title}</h1>
          <div className="pr-right">{right}</div>
        </header>
        {children}
      </div>
    </div>
  );
}

export function GameOver({ icon, headline, detail, isRecord, again, done }: { icon: string; headline: string; detail: string; isRecord: boolean; again: () => void; done: () => void }) {
  return (
    <div className="pr-over">
      <span className={`pr-over-icon${isRecord ? " record" : ""}`}><PIcon name={isRecord ? "trophy" : icon} size={64} /></span>
      {isRecord && <span className="pr-newbest">New best</span>}
      <h2 className="title-xl" style={{ textAlign: "center" }}>{headline}</h2>
      <p className="muted pr-over-detail">{detail}</p>
      <div className="stack pr-over-actions" style={{ ["--gap" as string]: "10px" }}>
        <button className="btn block" onClick={again} autoFocus><PIcon name="refresh" size={18} />Play again</button>
        <button className="btn block secondary" onClick={done}>Done</button>
      </div>
    </div>
  );
}
