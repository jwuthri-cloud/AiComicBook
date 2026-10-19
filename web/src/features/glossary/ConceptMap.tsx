// An explorable map of how glossary words connect (port of ConceptMapView.swift): the chosen word in the middle,
// its related words on an inner ellipse, a few of their neighbours further out. Click any word to walk the map.
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { type Store, type Term, useStore } from "../../content";
import { Icon, Pill, categoryTint, tinted } from "../../ui";
import { GIcon } from "./icons";
import { canGoBack, plural, relatedTermIds, stableHash } from "./logic";

interface Pt { x: number; y: number }
interface MapNode { id: string; ring: number; position: Pt; parent: string | null }

export function ConceptMapPage() {
  const { termId = "" } = useParams();
  const store = useStore();
  const navigate = useNavigate();
  const [history, setHistory] = useState<string[]>([]);
  const centerId = store.terms.has(termId) ? termId : store.termOfTheDay?.id ?? store.glossary[0]?.id ?? "";
  const center = store.terms.get(centerId);

  // The URL follows the centre word (replace, so browser Back leaves the map); the undo button walks back.
  const go = (id: string) => navigate(`/map/${id}`, { replace: true });
  const recenter = (id: string) => {
    if (id === centerId) return;
    setHistory((h) => [...h, centerId].slice(-30));
    go(id);
  };
  const undo = () => {
    const previous = history[history.length - 1];
    if (!previous) return;
    setHistory((h) => h.slice(0, -1));
    go(previous);
  };
  const random = () => {
    const pick = store.glossary[Math.floor(Math.random() * store.glossary.length)];
    if (pick) recenter(pick.id);
  };

  const box = useRef<HTMLDivElement>(null);
  const [size, setSize] = useState<{ w: number; h: number } | null>(null);
  useLayoutEffect(() => {
    const el = box.current;
    if (!el) return;
    const measure = () => {
      const r = el.getBoundingClientRect();
      setSize((s) => (s && Math.abs(s.w - r.width) < 1 && Math.abs(s.h - r.height) < 1 ? s : { w: r.width, h: r.height }));
    };
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  const nodes = useMemo(() => (size && center ? layout(store, centerId, size.w, size.h) : []), [store, centerId, center, size]);
  const positions = useTween(nodes);
  const byId = new Map(nodes.map((n) => [n.id, n]));
  const at = (n: MapNode) => positions.get(n.id) ?? n.position;

  if (!center) {
    return (
      <div className="narrow stack">
        <h1 className="title-l">Concept map</h1>
        <p className="muted">That word is not in the glossary.</p>
        <Link to="/glossary" className="btn secondary" style={{ alignSelf: "flex-start" }}>Open the glossary</Link>
      </div>
    );
  }

  const tint = categoryTint(center.category);
  const connections = relatedTermIds(store, center.id).length;

  return (
    <div className="stack gl-mappage" style={{ ["--gap" as string]: "14px", ...tinted(tint) }}>
      <header className="row" style={{ ["--gap" as string]: "8px" }}>
        <button className="gl-back" onClick={() => (canGoBack() ? navigate(-1) : navigate("/glossary"))}>
          <Icon name="left" size={16} />Back
        </button>
        <div className="stack" style={{ ["--gap" as string]: "0px", flex: 1, minWidth: 0, textAlign: "center" }}>
          <h1 className="title-m" style={{ fontWeight: 700 }}>Concept map</h1>
          <span className="tiny faint">Pick any word to walk the map</span>
        </div>
        <button className="iconbtn" onClick={undo} disabled={!history.length} aria-label="Back to previous word" title="Back to previous word">
          <GIcon name="undo" size={17} />
        </button>
        <button className="iconbtn" onClick={random} aria-label="Random word" title="Random word">
          <GIcon name="shuffle" size={17} />
        </button>
      </header>

      <div ref={box} className="gl-map" aria-label={`Words connected to ${center.term}`}>
        {size && (
          <svg className="gl-edges" width={size.w} height={size.h} aria-hidden="true">
            {nodes.map((node) => {
              const parent = node.parent ? byId.get(node.parent) : undefined;
              if (!parent) return null;
              const a = at(parent), b = at(node);
              // Gentle curves read better than straight spokes.
              const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
              const c = { x: mid.x + (size.w / 2 - mid.x) * 0.15, y: mid.y + (size.h / 2 - mid.y) * 0.15 };
              const term = store.terms.get(node.id);
              return (
                <path
                  key={`${parent.id}>${node.id}`}
                  d={`M${a.x},${a.y} Q${c.x},${c.y} ${b.x},${b.y}`}
                  fill="none"
                  style={{ stroke: term ? categoryTint(term.category) : "var(--ink-3)", strokeOpacity: node.ring === 1 ? 0.45 : 0.22, strokeWidth: node.ring === 1 ? 2 : 1.2 }}
                />
              );
            })}
          </svg>
        )}
        {nodes.map((node) => {
          const term = store.terms.get(node.id);
          if (!term) return null;
          const p = at(node);
          const spec = RINGS[node.ring];
          const style = { left: p.x, top: p.y, maxWidth: spec.max + (spec.padX + spec.border) * 2 + 2, ...tinted(categoryTint(term.category)) };
          const text = <span className="gl-node-text">{label(term, node.ring)}</span>;
          return node.ring === 0 ? (
            <div key={node.id} className="gl-node ring0" style={style} aria-current="true">{text}</div>
          ) : (
            <button key={node.id} className={`gl-node ring${node.ring}`} style={style} onClick={() => recenter(node.id)} aria-label={term.term} title={term.term}>
              {text}
            </button>
          );
        })}
      </div>

      <div className="card pad stack gl-mapcard" style={{ ["--gap" as string]: "8px" }}>
        <div className="row">
          <Pill text={center.category} tint={tint} />
          <span className="spacer" />
          <span className="tiny faint" style={{ fontWeight: 600 }}>{plural(connections, "connection")}</span>
        </div>
        <h2 className="title-m" style={{ fontWeight: 700 }}>{center.term}</h2>
        <p className="serif muted gl-clamp3">{center.short}</p>
        <Link to={`/glossary/${center.id}`} className="gl-open"><Icon name="glossary" size={16} />Open in glossary</Link>
      </div>
    </div>
  );
}

// ---------- layout ----------

/** Short names fit the map better: prefer a compact acronym. */
function label(term: Term, ring: number): string {
  if (ring > 0 && term.term.length > 22) {
    const short = term.aka.find((a) => a.length <= 8);
    if (short) return short;
  }
  return term.term;
}

const RINGS = [
  { weight: 700, size: 17, family: "--serif", max: 150, padX: 14, padY: 10, line: 21, border: 0 },
  { weight: 600, size: 13, family: "--rounded", max: 118, padX: 9, padY: 6, line: 16, border: 1.5 },
  { weight: 500, size: 11.5, family: "--rounded", max: 96, padX: 9, padY: 6, line: 14, border: 1 },
];

let ctx: CanvasRenderingContext2D | null = null;
const families: Record<string, string> = {};

/** Rendered size of a node, measured with the same font, for the overlap-free layout. */
function estimatedSize(term: Term | undefined, ring: number): { w: number; h: number } {
  if (!term) return { w: 0, h: 0 };
  const spec = RINGS[ring];
  families[spec.family] ??= getComputedStyle(document.documentElement).getPropertyValue(spec.family).trim() || "sans-serif";
  ctx ??= document.createElement("canvas").getContext("2d");
  let width = label(term, ring).length * spec.size * 0.55;
  if (ctx) {
    ctx.font = `${spec.weight} ${spec.size}px ${families[spec.family]}`;
    width = ctx.measureText(label(term, ring)).width;
  }
  const lines = width > spec.max ? 2 : 1;
  const edge = (spec.padX + spec.border) * 2;
  return { w: Math.ceil(Math.min(width, spec.max)) + edge + 2, h: lines * spec.line + (spec.padY + spec.border) * 2 };
}

/** Centre, up to 8 neighbours on an inner ellipse and a few of their neighbours outside, then nudged apart so no two labels overlap. */
function layout(store: Store, centerId: string, width: number, height: number): MapNode[] {
  const mid = { x: width / 2, y: height / 2 };
  const ids = [centerId];
  const rings = [0];
  const parents: (string | null)[] = [null];
  const targets: Pt[] = [mid];
  const inner = relatedTermIds(store, centerId).slice(0, 8);
  const used = new Set([centerId, ...inner]);
  const r1 = { w: width * 0.3, h: Math.min(height * 0.25, width * 0.45) };
  const r2 = { w: width * 0.38, h: height * 0.42 };
  const point = (r: { w: number; h: number }, angle: number) => ({ x: mid.x + r.w * Math.cos(angle), y: mid.y + r.h * Math.sin(angle) });
  // A stable rotation per word so the map doesn't always start at 12 o'clock.
  const spin = (Number(stableHash(centerId) % 360n) * Math.PI) / 180;
  let outerCount = 0;
  inner.forEach((id, i) => {
    const angle = spin + (2 * Math.PI * i) / Math.max(inner.length, 1);
    ids.push(id); rings.push(1); parents.push(centerId); targets.push(point(r1, angle));
    const perParent = inner.length > 5 ? 1 : 2;
    const children = relatedTermIds(store, id).filter((c) => !used.has(c)).slice(0, perParent);
    children.forEach((child, j) => {
      if (outerCount >= 9) return;
      used.add(child);
      outerCount += 1;
      const spread = perParent === 1 ? 0 : j === 0 ? -0.3 : 0.3;
      ids.push(child); rings.push(2); parents.push(id); targets.push(point(r2, angle + spread));
    });
  });

  // Relax: push overlapping labels apart, pull gently back towards their place on the rings.
  const sizes = ids.map((id, i) => estimatedSize(store.terms.get(id), rings[i]));
  const pos = targets.map((t) => ({ ...t }));
  const gap = 6;
  for (let iter = 0; iter < 160; iter++) {
    for (let a = 0; a < pos.length; a++) {
      for (let b = a + 1; b < pos.length; b++) {
        const dx = pos[b].x - pos[a].x, dy = pos[b].y - pos[a].y;
        const ox = (sizes[a].w + sizes[b].w) / 2 + gap - Math.abs(dx);
        const oy = (sizes[a].h + sizes[b].h) / 2 + gap - Math.abs(dy);
        if (ox <= 0 || oy <= 0) continue;
        // Separate along the cheaper axis; the centre word never moves.
        const wa = a === 0 ? 0 : b === 0 ? 1 : 0.5;
        const wb = 1 - wa;
        if (oy < ox) {
          const push = oy * (dy >= 0 ? 1 : -1);
          pos[a].y -= push * wa; pos[b].y += push * wb;
        } else {
          const push = ox * (dx >= 0 ? 1 : -1);
          pos[a].x -= push * wa; pos[b].x += push * wb;
        }
      }
    }
    for (let i = 1; i < pos.length; i++) {
      pos[i].x += (targets[i].x - pos[i].x) * 0.04;
      pos[i].y += (targets[i].y - pos[i].y) * 0.04;
      pos[i].x = Math.min(Math.max(pos[i].x, sizes[i].w / 2 + 4), width - sizes[i].w / 2 - 4);
      pos[i].y = Math.min(Math.max(pos[i].y, sizes[i].h / 2 + 4), height - sizes[i].h / 2 - 4);
    }
  }
  return ids.map((id, i) => ({ id, ring: rings[i], position: pos[i], parent: parents[i] }));
}

// ---------- animation ----------

/** Springs every node from where it was (new words grow out of their parent) to its new place. */
function useTween(nodes: MapNode[]): Map<string, Pt> {
  const [positions, setPositions] = useState<Map<string, Pt>>(new Map());
  const current = useRef<Map<string, Pt>>(new Map());

  useEffect(() => {
    const from = current.current;
    const targets = new Map(nodes.map((n) => [n.id, n.position]));
    const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
    if (reduce || from.size === 0) {
      current.current = targets;
      setPositions(targets);
      return;
    }
    const start = new Map<string, Pt>();
    for (const n of nodes) {
      const own = from.get(n.id);
      const parent = n.parent ? from.get(n.parent) ?? targets.get(n.parent) : undefined;
      start.set(n.id, own ?? parent ?? n.position);
    }
    const t0 = performance.now();
    const duration = 620;
    let raf = 0;
    const step = (now: number) => {
      const t = Math.min(1, (now - t0) / duration);
      const e = easeOutBack(t);
      const next = new Map<string, Pt>();
      for (const [id, to] of targets) {
        const s = start.get(id)!;
        next.set(id, { x: s.x + (to.x - s.x) * e, y: s.y + (to.y - s.y) * e });
      }
      current.current = next;
      setPositions(next);
      if (t < 1) raf = requestAnimationFrame(step);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, [nodes]);

  return positions;
}

function easeOutBack(t: number) {
  const c1 = 1.1, c3 = c1 + 1;
  return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2);
}
