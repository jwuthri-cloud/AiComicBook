// Practice progress in localStorage: Leitner boxes per glossary question (same semantics as QuizState.swift),
// streak days, XP and game bests. Keys: "practice.v1", "practice.best.match|speed|zoom".
import { useLocal } from "../../store";
import type { Term } from "../../content";

export interface PracticeRecord { box: number; seen: number; correct: number; last: number }
export interface PracticeSnapshot { records: Record<string, PracticeRecord>; activeDays: string[]; xp: number }

const EMPTY: PracticeSnapshot = { records: {}, activeDays: [], xp: 0 };
/** Days until a card in each box comes back. */
export const INTERVALS = [0, 1, 3, 7, 21];
const DAY = 86_400_000;

export const dayKey = (d = new Date()) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
export const meaningId = (termId: string) => `term:${termId}:meaning`;
export const nameId = (termId: string) => `term:${termId}:name`;

export function isDue(snap: PracticeSnapshot, id: string): boolean {
  const r = snap.records[id];
  return !!r && Date.now() - r.last >= INTERVALS[r.box] * DAY;
}

export function isMastered(snap: PracticeSnapshot, id: string): boolean {
  return (snap.records[id]?.box ?? 0) >= 3;
}

export function usePractice() {
  const [stored, set] = useLocal<PracticeSnapshot>("practice.v1", EMPTY);
  const snap: PracticeSnapshot = { ...EMPTY, ...stored };
  return {
    snap,
    isDue: (id: string) => isDue(snap, id),
    isMastered: (id: string) => isMastered(snap, id),
    /** Records an answer from any practice mode in the spaced-repetition boxes. */
    mark: (id: string, correct: boolean, points = 10) =>
      set((old) => {
        const s = { ...EMPTY, ...old };
        const r = { ...(s.records[id] ?? { box: 0, seen: 0, correct: 0, last: 0 }) };
        r.seen += 1;
        r.last = Date.now();
        if (correct) {
          r.correct += 1;
          r.box = Math.min(r.box + 1, INTERVALS.length - 1);
        } else {
          r.box = 0;
        }
        return { ...s, records: { ...s.records, [id]: r }, xp: s.xp + (correct ? points : 0) };
      }),
    /** Bonus points for games, without touching review boxes. */
    award: (points: number) => set((old) => ({ ...EMPTY, ...old, xp: (old.xp ?? 0) + Math.max(0, Math.round(points)) })),
    /** A finished game or deck counts towards the streak, like a quiz. */
    practiced: () =>
      set((old) => {
        const s = { ...EMPTY, ...old };
        const today = dayKey();
        return s.activeDays.includes(today) ? s : { ...s, activeDays: [...s.activeDays, today].slice(-400) };
      }),
  };
}

export const useBestMatch = () => useLocal<number>("practice.best.match", 0);
export const useBestSpeed = () => useLocal<number>("practice.best.speed", 0);
export const useBestZoom = () => useLocal<number>("practice.best.zoom", 0);

/** Game records for tiles elsewhere (Quiz "Play"): match is seconds (lower is better, 0 = none), speed points, zoom out of 24. */
export function usePracticeBests() {
  const [match] = useBestMatch();
  const [speed] = useBestSpeed();
  const [zoom] = useBestZoom();
  return { match, speed, zoom };
}

// ---------- decks (port of PracticeDecks) ----------

/** Due or missed words first, then unseen, then the rest (weighted sampling without replacement). */
export function weighted(terms: Term[], snap: PracticeSnapshot, count: number): Term[] {
  const weight = (t: Term) => {
    const id = meaningId(t.id);
    const r = snap.records[id];
    if (!r) return 2.5;
    return r.box === 0 ? 5 : isDue(snap, id) ? 3 : 0.4;
  };
  return terms
    .map((t) => ({ t, key: -Math.log(0.0001 + Math.random() * 0.9999) / weight(t) }))
    .sort((a, b) => a.key - b.key)
    .slice(0, count)
    .map((x) => x.t);
}

export function shuffled<T>(items: readonly T[]): T[] {
  const a = [...items];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

export const randomElement = <T,>(items: readonly T[]): T | undefined => items[Math.floor(Math.random() * items.length)];
