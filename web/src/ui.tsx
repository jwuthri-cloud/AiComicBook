// Shared building blocks (web twins of Theme.swift helpers). Feature folders import from here; keep it generic.
import type { CSSProperties, ReactNode } from "react";
import { Link, useNavigate } from "react-router-dom";
import { type Book, type Store, type Term, type TermMatch, url, useStore } from "./content";

export const tintVar = (name: string) => `var(--${["teal", "violet", "amber", "lime", "coral"].includes(name) ? name : "accent"})`;

export function categoryTint(category: string): string {
  switch (category) {
    case "AI Safety": return tintVar("violet");
    case "Interpretability": return tintVar("teal");
    case "Research Methods": case "Git": return tintVar("coral");
    case "Machine Learning": case "LLMs": return tintVar("amber");
    case "Algorithms": case "Data Structures": return tintVar("lime");
    default: return "var(--accent)";
  }
}

export const tinted = (tint: string, extra?: CSSProperties): CSSProperties => ({ ["--tint" as string]: tint, ...extra });

export function Pill({ text, tint, icon }: { text: string; tint?: string; icon?: ReactNode }) {
  return <span className="pill" style={tint ? tinted(tint) : undefined}>{icon}{text}</span>;
}

export function SectionHeader({ title, subtitle, icon, tint = "var(--accent)", action }: { title: string; subtitle?: string; icon?: ReactNode; tint?: string; action?: ReactNode }) {
  return (
    <div className="section-header" style={tinted(tint)}>
      {icon && <span className="icon">{icon}</span>}
      <div className="stack" style={{ ["--gap" as string]: "2px", flex: 1 }}>
        <h2 className="title-m" style={{ fontWeight: 700 }}>{title}</h2>
        {subtitle && <span className="small muted">{subtitle}</span>}
      </div>
      {action}
    </div>
  );
}

export function Segmented<T extends string>({ value, options, onChange, labels }: { value: T; options: readonly T[]; onChange: (v: T) => void; labels?: Record<string, string> }) {
  return (
    <div className="segmented" role="tablist">
      {options.map((o) => (
        <button key={o} role="tab" aria-selected={o === value} className={o === value ? "on" : ""} onClick={() => onChange(o)}>
          {labels?.[o] ?? o}
        </button>
      ))}
    </div>
  );
}

export function BookCover({ book, width = 120 }: { book: Book; width?: number }) {
  return (
    <div className="cover" style={{ width }}>
      <img src={url(book.cover)} alt="" loading="lazy" />
    </div>
  );
}

export function TermChip({ term, short }: { term: Term; short?: boolean }) {
  return (
    <Link to={`/glossary/${term.id}`} className="chip" style={tinted(categoryTint(term.category))}>
      {short ? term.aka.find((a) => a.length <= 6) ?? term.term : term.term}
    </Link>
  );
}

/** Text with glossary terms turned into links. Pure: `seen` lists terms NOT to link again (it is never mutated). */
export function LinkedText({ text, seen, exclude, tint }: { text: string; seen?: Set<string>; exclude?: Set<string>; tint?: string }) {
  const store = useStore();
  return <Linked text={text} matches={store.matcher.matches(text, new Set(seen), exclude)} tint={tint} />;
}

/** First-mention links across several texts in order (e.g. a page's panels); compute once, render with <Linked>. */
export function linkAll(store: Store, texts: string[], exclude?: Set<string>): TermMatch[][] {
  const seen = new Set<string>();
  return texts.map((t) => store.matcher.matches(t, seen, exclude));
}

export function Linked({ text, matches, tint }: { text: string; matches: TermMatch[]; tint?: string }) {
  const navigate = useNavigate();
  if (!matches.length) return <>{text}</>;
  const out: ReactNode[] = [];
  let at = 0;
  for (const m of matches) {
    if (m.start > at) out.push(text.slice(at, m.start));
    out.push(
      <a key={m.start} className="term-link" style={tint ? tinted(tint) : undefined} onClick={() => navigate(`/glossary/${m.termId}`)}>
        {text.slice(m.start, m.end)}
      </a>,
    );
    at = m.end;
  }
  out.push(text.slice(at));
  return <>{out}</>;
}

/** Glossary ids linked anywhere in these texts, in order of first mention. */
export function termsIn(store: Store, texts: string[], exclude: Set<string>): Term[] {
  const seen = new Set<string>();
  for (const t of texts) store.matcher.matches(t, seen, exclude);
  return [...seen].map((id) => store.terms.get(id)!).filter(Boolean);
}

export function formatDuration(seconds: number) {
  const s = Math.round(seconds);
  return s >= 60 ? `${Math.floor(s / 60)}m ${s % 60}s` : `${s}s`;
}

/** Minimal inline icons (SF Symbols are not on the web). */
export function Icon({ name, size = 18 }: { name: string; size?: number }) {
  const p = ICONS[name] ?? ICONS.dot;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {p}
    </svg>
  );
}

const ICONS: Record<string, ReactNode> = {
  dot: <circle cx="12" cy="12" r="3" />,
  books: <><path d="M4 19V5a1 1 0 0 1 1-1h3v15H5a1 1 0 0 1-1-1z" /><path d="M8 4h4v15H8z" /><path d="m14 5 3.5-1 3 14-3.5 1z" /></>,
  map: <><path d="m3 6 6-2 6 2 6-2v14l-6 2-6-2-6 2z" /><path d="M9 4v14M15 6v14" /></>,
  check: <path d="m5 12 5 5 9-10" />,
  quiz: <><circle cx="12" cy="12" r="9" /><path d="m8 12 3 3 5-6" /></>,
  glossary: <><path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z" /><path d="M5 17a3 3 0 0 1 3-3h11" /></>,
  search: <><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5" /></>,
  play: <path d="M7 5v14l11-7z" fill="currentColor" />,
  pause: <><path d="M8 5v14M16 5v14" /></>,
  close: <path d="M6 6l12 12M18 6 6 18" />,
  left: <path d="m15 6-6 6 6 6" />,
  right: <path d="m9 6 6 6-6 6" />,
  down: <path d="m6 9 6 6 6-6" />,
  bookmark: <path d="M6 4h12v16l-6-4-6 4z" />,
  headphones: <><path d="M4 15v-3a8 8 0 0 1 16 0v3" /><rect x="3" y="14" width="5" height="6" rx="2" /><rect x="16" y="14" width="5" height="6" rx="2" /></>,
  sparkles: <><path d="M12 3l1.8 4.7L18.5 9.5l-4.7 1.8L12 16l-1.8-4.7L5.5 9.5l4.7-1.8z" /><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8z" /></>,
  settings: <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>,
  video: <><rect x="3" y="5" width="18" height="14" rx="3" /><path d="m10 9 5 3-5 3z" fill="currentColor" /></>,
  image: <><rect x="3" y="4" width="18" height="16" rx="3" /><circle cx="9" cy="10" r="2" /><path d="m21 16-5-5-9 9" /></>,
  text: <path d="M4 6h16M4 12h16M4 18h10" />,
  share: <><path d="M12 3v12M7 8l5-5 5 5" /><path d="M5 13v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6" /></>,
  bulb: <><path d="M9 18h6M10 21h4" /><path d="M12 3a6 6 0 0 0-4 10.5c.8.8 1 1.5 1 2.5h6c0-1 .2-1.7 1-2.5A6 6 0 0 0 12 3z" /></>,
  warn: <><path d="M12 3 2 20h20z" /><path d="M12 10v4M12 17h.01" /></>,
  flag: <><path d="M5 21V4" /><path d="M5 4h11l-2 4 2 4H5" /></>,
  wrench: <path d="M14.7 6.3a4 4 0 0 0-5.4 5.4L3 18l3 3 6.3-6.3a4 4 0 0 0 5.4-5.4l-2.5 2.5-2.4-.6-.6-2.4z" />,
  cards: <><rect x="3" y="6" width="13" height="15" rx="2" /><path d="M8 3h11a2 2 0 0 1 2 2v13" /></>,
  graph: <><circle cx="6" cy="6" r="2.5" /><circle cx="18" cy="8" r="2.5" /><circle cx="10" cy="18" r="2.5" /><path d="m8 7 8 1M7 8l2 8M12 17l5-7" /></>,
  grad: <><path d="m2 9 10-5 10 5-10 5z" /><path d="M6 11v5c3 2 9 2 12 0v-5" /></>,
  turn: <path d="M6 5v6a3 3 0 0 0 3 3h9M14 10l4 4-4 4" />,
  eye: <><path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12z" /><circle cx="12" cy="12" r="3" /></>,
  key: <><circle cx="8" cy="15" r="4" /><path d="m11 12 9-9M17 6l3 3" /></>,
  copy: <><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3" /></>,
  flame: <path d="M12 3c1 4 6 6 6 11a6 6 0 0 1-12 0c0-3 2-4 3-7 1 2 2 3 3 3 0-3-1-5 0-7z" />,
  refresh: <><path d="M20 11a8 8 0 1 0-2.3 5.7" /><path d="M20 4v7h-7" /></>,
};
