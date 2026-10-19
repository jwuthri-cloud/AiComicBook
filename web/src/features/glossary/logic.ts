// Glossary helpers ported from ContentStore.swift (term graph), GlossaryView.swift (search) and SearchEngine.swift.
import type { Store, Term } from "../../content";

const graphs = new WeakMap<Store, Map<string, string[]>>();

/** Undirected "related" links between glossary terms, best-connected first (ContentStore.relatedTermIds). */
export function relatedTermIds(store: Store, id: string): string[] {
  let graph = graphs.get(store);
  if (!graph) {
    const links = new Map<string, Set<string>>();
    const link = (a: string, b: string) => {
      let set = links.get(a);
      if (!set) links.set(a, (set = new Set()));
      set.add(b);
    };
    for (const term of store.glossary) {
      for (const other of term.related) {
        if (other === term.id || !store.terms.has(other)) continue;
        link(term.id, other);
        link(other, term.id);
      }
    }
    const degree = (x: string) => links.get(x)?.size ?? 0;
    graph = new Map();
    for (const [key, ids] of links) {
      graph.set(key, [...ids].sort((a, b) => degree(b) - degree(a) || (a < b ? -1 : a > b ? 1 : 0)));
    }
    graphs.set(store, graph);
  }
  return graph.get(id) ?? [];
}

/** Levenshtein distance that gives up (returns limit + 1) once every path exceeds `limit`. */
export function editDistance(a: string, b: string, limit: number): number {
  const x = [...a], y = [...b];
  if (!x.length) return y.length;
  if (!y.length) return x.length;
  let previous = Array.from({ length: y.length + 1 }, (_, i) => i);
  for (let i = 1; i <= x.length; i++) {
    const current = [i, ...new Array<number>(y.length).fill(0)];
    let rowMin = current[0];
    for (let j = 1; j <= y.length; j++) {
      current[j] = Math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (x[i - 1] === y[j - 1] ? 0 : 1));
      rowMin = Math.min(rowMin, current[j]);
    }
    if (rowMin > limit) return limit + 1;
    previous = current;
  }
  return previous[y.length];
}

/** Name, aka, then the short line (4+ letters), with one typo of tolerance on the name itself. */
export function matchesTerm(term: Term, query: string): boolean {
  const q = query.toLowerCase();
  const fields = [term.term, ...term.aka].map((f) => f.toLowerCase());
  if (fields.some((f) => f.includes(q))) return true;
  if (q.length >= 4 && term.short.toLowerCase().includes(q)) return true;
  return q.length >= 4 && fields.some((f) => editDistance([...f].slice(0, [...q].length).join(""), q, 1) <= 1);
}

/** First letter for the A–Z sections; "#" for digits and symbols. */
export function sortLetter(term: Term): string {
  const first = term.term.normalize("NFD").replace(/\p{M}/gu, "").charAt(0);
  return /\p{L}/u.test(first) ? first.toUpperCase() : "#";
}

/** FNV-1a 64-bit, so the same word always gets the same map rotation. */
export function stableHash(s: string): bigint {
  let h = 0xcbf29ce484222325n;
  for (const byte of new TextEncoder().encode(s)) {
    h ^= BigInt(byte);
    h = (h * 0x100000001b3n) & 0xffffffffffffffffn;
  }
  return h;
}

export const plural = (n: number, one: string, many = `${one}s`) => `${n} ${n === 1 ? one : many}`;

/** Router-aware back: pop history when this app pushed the current entry, else go to `fallback`. */
export function canGoBack(): boolean {
  const state = window.history.state as { idx?: number } | null;
  return (state?.idx ?? 0) > 0;
}
