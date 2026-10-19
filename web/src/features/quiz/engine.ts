// Pure quiz logic: port of app/Panels/Model/Quiz.swift (QuizItem, Leitner boxes, session builder).
import type { Question, Store, Term } from "../../content";

/** One question as shown in a session: options shuffled, linked to a page or a glossary term. */
export interface QuizItem {
  id: string;
  prompt: string;
  options: string[];
  correct: number;
  explanation: string;
  difficulty: number;
  pageId?: string;
  termId?: string;
}

export type QuizKind =
  | { mode: "daily" }
  | { mode: "quick" }
  | { mode: "hard" }
  | { mode: "review" }
  | { mode: "words"; category?: string }
  | { mode: "book"; id: string }
  | { mode: "collection"; id: string }
  | { mode: "retry"; ids: string[] };

export interface QuizSession {
  kind: QuizKind;
  title: string;
  items: QuizItem[];
}

// ---------- progress (Leitner boxes + streaks) ----------

export interface QuizRecord { box: number; seen: number; correct: number; last: number }
export interface QuizSnapshot {
  records: Record<string, QuizRecord>;
  activeDays: string[];
  dailyDone?: string | null;
  xp: number;
  sessions: number;
}

export const EMPTY_SNAPSHOT: QuizSnapshot = { records: {}, activeDays: [], dailyDone: null, xp: 0, sessions: 0 };

/** Days until a question in each box comes back. */
export const INTERVALS = [0, 1, 3, 7, 21];
const DAY_MS = 86_400_000;

export const dayKey = (d: Date = new Date()) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;

export const isMastered = (s: QuizSnapshot, id: string) => (s.records[id]?.box ?? 0) >= 3;

export function isDue(s: QuizSnapshot, id: string, now = Date.now()): boolean {
  const r = s.records[id];
  if (!r) return false;
  return now - r.last >= INTERVALS[Math.min(r.box, INTERVALS.length - 1)] * DAY_MS;
}

/** Questions answered wrong last time (box 0) or due again. */
export function needsReview(s: QuizSnapshot, id: string, now = Date.now()): boolean {
  const r = s.records[id];
  if (!r) return false;
  return r.box === 0 || isDue(s, id, now);
}

/** Consecutive days with a finished quiz, counting today or yesterday as the latest. */
export function streak(s: QuizSnapshot, now = new Date()): number {
  const days = new Set(s.activeDays);
  const date = new Date(now);
  if (!days.has(dayKey(date))) date.setDate(date.getDate() - 1);
  let count = 0;
  while (days.has(dayKey(date))) {
    count += 1;
    date.setDate(date.getDate() - 1);
  }
  return count;
}

export function accuracy(s: QuizSnapshot): number | null {
  let seen = 0;
  let correct = 0;
  for (const r of Object.values(s.records)) { seen += r.seen; correct += r.correct; }
  return seen > 0 ? correct / seen : null;
}

export function recordAnswer(s: QuizSnapshot, id: string, correct: boolean, points: number, now = Date.now()): QuizSnapshot {
  const r = { ...(s.records[id] ?? { box: 0, seen: 0, correct: 0, last: 0 }) };
  r.seen += 1;
  r.last = now;
  if (correct) {
    r.correct += 1;
    r.box = Math.min(r.box + 1, INTERVALS.length - 1);
  } else {
    r.box = 0;
  }
  return { ...s, records: { ...s.records, [id]: r }, xp: s.xp + (correct ? points : 0) };
}

export function recordFinish(s: QuizSnapshot, kind: QuizKind, now = new Date()): QuizSnapshot {
  const today = dayKey(now);
  const days = s.activeDays.includes(today) ? s.activeDays : [...s.activeDays, today];
  return {
    ...s,
    activeDays: days.slice(-400),
    dailyDone: kind.mode === "daily" ? today : s.dailyDone,
    sessions: s.sessions + 1,
  };
}

export const pointsFor = (item: QuizItem) => 10 + 5 * (item.difficulty - 1);

// ---------- randomness ----------

export type Rng = () => number;

/** FNV-1a over UTF-8: the same string gives the same number on every visit. */
export function stableHash(s: string): number {
  let h = 0x811c9dc5;
  for (const byte of new TextEncoder().encode(s)) {
    h ^= byte;
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h;
}

/** Deterministic generator (mulberry32) so the daily quiz is the same all day. */
export function seeded(seed: number): Rng {
  let a = seed >>> 0 || 0x9e3779b9;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function shuffled<T>(items: readonly T[], rng: Rng = Math.random): T[] {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

const isTrueFalse = (options: string[]) => options.length === 2 && options[0] === "True" && options[1] === "False";

/** Shuffles options (True/False stays in order) and tracks where the answer went. */
function arrange(options: string[], correct: number): { options: string[]; correct: number } {
  if (isTrueFalse(options)) return { options, correct };
  const order = shuffled(options.map((_, i) => i));
  return { options: order.map((i) => options[i]), correct: order.indexOf(correct) };
}

// ---------- items ----------

function itemFrom(q: Question): QuizItem {
  return {
    id: q.id, prompt: q.prompt, ...arrange(q.options, q.answer),
    explanation: q.explanation, difficulty: q.difficulty, pageId: q.pageId,
  };
}

export const pageItems = (store: Store) => store.quiz.map(itemFrom);

export function questionsForBook(store: Store, bookId: string): Question[] {
  const book = store.books.get(bookId);
  if (!book) return [];
  const ids = new Set(book.pages.map((p) => p.id));
  return store.quiz.filter((q) => ids.has(q.pageId));
}

export function questionsForCollection(store: Store, collectionId: string): Question[] {
  const c = store.collectionsById.get(collectionId);
  if (!c) return [];
  const ids = new Set(c.books.flatMap((b) => b.pages.map((p) => p.id)));
  return store.quiz.filter((q) => ids.has(q.pageId));
}

const distractorCache = new WeakMap<Store, Map<string, Term[]>>();

/** Stable distractors per term so a word question reads the same each time it comes back. */
function distractors(store: Store, term: Term): Term[] {
  let cache = distractorCache.get(store);
  if (!cache) distractorCache.set(store, (cache = new Map()));
  let hit = cache.get(term.id);
  if (!hit) {
    let siblings = store.glossary.filter((t) => t.category === term.category && t.id !== term.id && !term.related.includes(t.id));
    if (siblings.length < 3) siblings = store.glossary.filter((t) => t.id !== term.id);
    hit = shuffled(siblings, seeded(stableHash(term.id))).slice(0, 3);
    cache.set(term.id, hit);
  }
  return hit;
}

export const termItemIds = (termId: string) => [`term:${termId}:name`, `term:${termId}:meaning`];

/** Glossary questions: "which word matches this definition?" and the reverse. */
export function termItems(store: Store, category?: string): QuizItem[] {
  const out: QuizItem[] = [];
  for (const term of store.glossary) {
    if (category && term.category !== category) continue;
    const group = shuffled([term, ...distractors(store, term)]);
    const answer = group.indexOf(term);
    const [nameId, meaningId] = termItemIds(term.id);
    out.push({
      id: nameId, prompt: `Which word means: “${term.short}”`,
      options: group.map((t) => t.term), correct: answer,
      explanation: term.definition, difficulty: 1, pageId: term.pages[0], termId: term.id,
    });
    const group2 = shuffled(group);
    out.push({
      id: meaningId, prompt: `What does “${term.term}” mean?`,
      options: group2.map((t) => t.short), correct: group2.indexOf(term),
      explanation: term.definition, difficulty: 2, pageId: term.pages[0], termId: term.id,
    });
  }
  return out;
}

const idCache = new WeakMap<Store, string[]>();

/** Every question id in the bank: page questions plus two per glossary term. */
export function allItemIds(store: Store): string[] {
  let ids = idCache.get(store);
  if (!ids) {
    ids = [...store.quiz.map((q) => q.id), ...store.glossary.flatMap((t) => termItemIds(t.id))];
    idCache.set(store, ids);
  }
  return ids;
}

export function mastery(s: QuizSnapshot, ids: string[]): number {
  if (!ids.length) return 0;
  return ids.filter((id) => isMastered(s, id)).length / ids.length;
}

/** Weighted sample: wrong answers and due questions first, then unseen, then the rest. */
function pick(s: QuizSnapshot, items: QuizItem[], count: number, rng: Rng = Math.random): QuizItem[] {
  const now = Date.now();
  const keyed = items.map((item) => {
    const r = s.records[item.id];
    const w = r ? (r.box === 0 ? 5 : isDue(s, item.id, now) ? 3 : 0.3) : 2.5;
    // Exponential keys give weighted sampling without replacement.
    return { item, key: -Math.log(0.0001 + rng() * 0.9999) / w };
  });
  keyed.sort((a, b) => a.key - b.key);
  const chosen: QuizItem[] = [];
  const pagesUsed = new Set<string>();
  for (const { item } of keyed) {
    // Spread questions across pages.
    if (item.pageId && !item.termId) {
      if (pagesUsed.has(item.pageId) && items.length > count * 2) continue;
      pagesUsed.add(item.pageId);
    }
    chosen.push(item);
    if (chosen.length === count) break;
  }
  return chosen;
}

export function buildSession(store: Store, s: QuizSnapshot, kind: QuizKind): QuizSession {
  switch (kind.mode) {
    case "daily": {
      const rng = seeded(stableHash(dayKey()));
      const pages = pick(s, pageItems(store), 8, rng);
      const words = pick(s, termItems(store), 2, rng);
      return { kind, title: "Daily 10", items: shuffled([...pages, ...words], rng) };
    }
    case "quick":
      return { kind, title: "Quick 5", items: pick(s, [...pageItems(store), ...termItems(store)], 5) };
    case "hard":
      return { kind, title: "Hard mode", items: shuffled(pageItems(store).filter((i) => i.difficulty === 3)).slice(0, 10) };
    case "review": {
      const now = Date.now();
      const due = [...pageItems(store), ...termItems(store)].filter((i) => needsReview(s, i.id, now));
      return { kind, title: "Review", items: shuffled(due).slice(0, 12) };
    }
    case "words":
      return { kind, title: kind.category ? `${kind.category} words` : "Word drill", items: pick(s, termItems(store, kind.category), 10) };
    case "book": {
      const book = store.books.get(kind.id);
      const all = questionsForBook(store, kind.id).map(itemFrom);
      // Short books: everything, in reading order. Long books: a weighted sample.
      let chosen = all;
      if (all.length > 15) chosen = pick(s, all, 12);
      else if (book) {
        const at = new Map(book.pages.map((p, i) => [p.id, i]));
        chosen = [...all].sort((a, b) => (at.get(a.pageId!) ?? 0) - (at.get(b.pageId!) ?? 0) || a.id.localeCompare(b.id, undefined, { numeric: true }));
      }
      return { kind, title: book?.title ?? "Book quiz", items: chosen };
    }
    case "collection":
      return {
        kind,
        title: store.collectionsById.get(kind.id)?.title ?? "Collection quiz",
        items: pick(s, questionsForCollection(store, kind.id).map(itemFrom), 12),
      };
    case "retry": {
      const all = new Map([...pageItems(store), ...termItems(store)].map((i) => [i.id, i]));
      return { kind, title: "Second chance", items: kind.ids.map((id) => all.get(id)).filter((i): i is QuizItem => !!i) };
    }
  }
}

// ---------- URLs ----------

/** /quiz/play?mode=… for a session kind (other features can link here too). */
export function quizPath(kind: QuizKind): string {
  const q = new URLSearchParams({ mode: kind.mode });
  if (kind.mode === "words" && kind.category) q.set("category", kind.category);
  if (kind.mode === "book" || kind.mode === "collection") q.set("id", kind.id);
  if (kind.mode === "retry") q.set("ids", kind.ids.join(","));
  return `/quiz/play?${q}`;
}

export function parseKind(q: URLSearchParams): QuizKind {
  const id = q.get("id") ?? "";
  switch (q.get("mode")) {
    case "quick": return { mode: "quick" };
    case "hard": return { mode: "hard" };
    case "review": return { mode: "review" };
    case "words": return { mode: "words", category: q.get("category") || undefined };
    case "book": return { mode: "book", id };
    case "collection": return { mode: "collection", id };
    case "retry": return { mode: "retry", ids: (q.get("ids") ?? "").split(",").filter(Boolean) };
    default: return { mode: "daily" };
  }
}
