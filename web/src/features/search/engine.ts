// Offline search over pages, books, glossary terms and playbook tools/experiments (port of SearchEngine.swift).
//
// Ranking combines weighted fields (title > keywords > headings > body), prefix matching while typing, typo
// tolerance (edit distance), and acronym/synonym expansion from the glossary and store.synonyms.
// The Swift version's on-device sentence-embedding rerank is not ported (no embedding model on the web).
import type { Store, TreeNode } from "../../content";

export type Kind = "term" | "page" | "book" | "tool" | "experiment";

export interface Hit { key: string; kind: Kind; itemId: string; score: number; matched: Set<string> }

interface Doc { kind: Kind; id: string; title: string }
interface Posting { doc: number; weight: number }

const STOP_WORDS = new Set([
  "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "is", "are", "it", "its", "be", "by", "as",
  "at", "this", "that", "with", "from", "can", "do", "does", "what", "how", "why", "when", "who", "which",
  "about", "into", "than", "then", "there", "their", "they", "them", "you", "your", "we", "our", "i", "me",
  "my", "so", "if", "not", "but", "was", "were", "has", "have", "had", "will", "would", "should", "could",
  // Web addition: apostrophe fragments ("model's", "don't") would otherwise count as query words.
  "s", "t",
]);

export function surfaceWords(text: string): string[] {
  return text.normalize("NFD").replace(/\p{M}/gu, "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

export function stem(w: string): string {
  if (w.length <= 4) return w;
  for (const suffix of ["ing", "ies", "es", "ed", "s"]) {
    if (w.endsWith(suffix) && w.length - suffix.length >= 3) {
      if (suffix === "ies") return w.slice(0, -3) + "y";
      if (suffix === "s" && w.endsWith("ss")) return w;
      return w.slice(0, -suffix.length);
    }
  }
  return w;
}

export function tokenize(text: string): string[] {
  return surfaceWords(text).map(stem).filter((t) => t && !STOP_WORDS.has(t));
}

export function editDistance(a: string, b: string, limit: number): number {
  if (!a.length) return b.length;
  if (!b.length) return a.length;
  let previous = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const current = [i];
    let rowMin = i;
    for (let j = 1; j <= b.length; j++) {
      current[j] = Math.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
      rowMin = Math.min(rowMin, current[j]);
    }
    if (rowMin > limit) return limit + 1;
    previous = current;
  }
  return previous[b.length];
}

/** Does this written word match one of the hit's matched tokens (prefix either way)? */
export function wordMatches(word: string, tokens: Set<string>): boolean {
  return tokenize(word).some((tok) => tok.length >= 3 && [...tokens].some((t) => t.length >= 3 && (tok.startsWith(t) || t.startsWith(tok))));
}

/** Short excerpt around the first matched word, for result rows. */
export function snippet(text: string, tokens: Set<string>, radius = 70): string {
  if (!tokens.size) return text.slice(0, radius * 2);
  const words = text.split(/\s+/).filter(Boolean);
  const hit = words.findIndex((w) => wordMatches(w, tokens));
  if (hit < 0) return text.slice(0, radius * 2);
  const start = Math.max(0, hit - 6);
  const end = Math.min(words.length, start + 26);
  let s = words.slice(start, end).join(" ");
  if (start > 0) s = "…" + s;
  if (end < words.length) s += "…";
  return s;
}

function treeTexts(nodes: TreeNode[], steps: string[], rest: string[]) {
  for (const n of nodes) {
    steps.push(n.step);
    if (n.how) rest.push(n.how);
    if (n.outcome) rest.push(n.outcome);
    for (const b of n.branches ?? []) {
      rest.push(b.if);
      treeTexts(b.then, steps, rest);
    }
  }
}

export class SearchEngine {
  private docs: Doc[] = [];
  private index = new Map<string, Posting[]>();
  private vocabulary: string[] = [];
  private surfaceToStem = new Map<string, string>();
  private surfaces: string[] = [];
  private idf = new Map<string, number>();
  private synonyms = new Map<string, string[]>();

  constructor(store: Store) {
    const addSynonyms = (key: string, words: string[]) => this.synonyms.set(key, [...(this.synonyms.get(key) ?? []), ...words]);

    for (const term of store.glossary) {
      this.add("term", term.id, term.term, [
        [term.term, 8], [term.aka.join(" "), 8], [term.short, 2], [term.definition, 1], [term.category, 0.5],
      ]);
      // Acronym <-> expansion, so "rlhf" also finds "reinforcement learning from human feedback".
      const tokenSets = [term.term, ...term.aka].map(tokenize).filter((t) => t.length);
      for (const tokens of tokenSets) {
        if (tokens.length !== 1) continue;
        const others = tokenSets.filter((t) => t.join(" ") !== tokens.join(" ")).flat();
        if (others.length) addSynonyms(tokens[0], others);
      }
    }
    for (const collection of store.collections) {
      for (const book of collection.books) {
        this.add("book", book.id, book.title, [
          [book.title, 6], [book.subtitle, 2], [collection.title, 1.5], [book.objectives.join(" "), 1.5],
        ]);
        for (const page of book.pages) {
          const fields: [string, number][] = [
            [page.title, 6], [page.printedTitle ?? "", 3], [page.subtitle, 3],
            [page.keywords.join(" "), 4], [page.footer, 1.5], [page.summary, 1],
            [book.title, 1], [page.wordKey, 1],
          ];
          for (const panel of page.panels) {
            fields.push([panel.heading, 2.5], [panel.body, 1]);
            if (panel.code) fields.push([panel.code, 0.5]);
          }
          this.add("page", page.id, page.title, fields);
        }
      }
    }
    // Web addition: the playbook is searchable too.
    for (const tool of store.playbook?.tools ?? []) {
      this.add("tool", tool.id, tool.name, [
        [tool.name, 6], [tool.what, 2], [tool.useWhen, 1.5], [tool.catch, 1], [tool.category, 0.5],
      ]);
    }
    for (const e of store.playbook?.experiments ?? []) {
      const steps: string[] = [];
      const rest: string[] = [];
      treeTexts(e.tree, steps, rest);
      this.add("experiment", e.id, e.question, [
        [e.question, 6], [e.chain, 2], [steps.join(" "), 1.5], [e.theme, 1], [rest.join(" "), 0.8],
        [e.confound, 0.8], [e.success, 0.8], [e.example, 0.8],
      ]);
    }

    // Shorter words first, so prefix expansion prefers the closest completions.
    this.vocabulary = [...this.index.keys()].sort((a, b) => a.length - b.length || (a < b ? -1 : 1));
    const n = this.docs.length;
    for (const [token, postings] of this.index) {
      const df = postings.length; // one posting per (token, doc)
      this.idf.set(token, Math.log(1 + (n - df + 0.5) / (df + 0.5)));
    }
    for (const [word, phrases] of Object.entries(store.synonyms)) {
      const key = tokenize(word).join(" ");
      if (key) addSynonyms(key, phrases.flatMap(tokenize));
    }
    this.surfaces = [...this.surfaceToStem.keys()];
  }

  private add(kind: Kind, id: string, title: string, fields: [string, number][]) {
    const doc = this.docs.length;
    this.docs.push({ kind, id, title });
    const weights = new Map<string, number>();
    for (const [text, weight] of fields) {
      if (weight <= 0 || !text) continue;
      for (const surface of surfaceWords(text)) if (surface.length >= 4) this.surfaceToStem.set(surface, stem(surface));
      for (const token of tokenize(text)) {
        // Saturating term frequency: repeated words help a little, not linearly.
        weights.set(token, Math.min((weights.get(token) ?? 0) + weight, weight * 2.2));
      }
    }
    for (const [token, weight] of weights) {
      const list = this.index.get(token);
      if (list) list.push({ doc, weight }); else this.index.set(token, [{ doc, weight }]);
    }
  }

  search(query: string, limit = 60): Hit[] {
    const surfaceQuery = surfaceWords(query).filter((w) => stem(w) && !STOP_WORDS.has(stem(w)));
    const tokens = surfaceQuery.map(stem);
    if (!tokens.length) return [];

    const scores = new Map<number, number>();
    const matched = new Map<number, Set<string>>();
    const coverage = new Map<number, number>();

    tokens.forEach((token, position) => {
      const isLast = position === tokens.length - 1;
      const expansions: [string, number][] = [[token, 1]];
      // While typing, the last word is probably incomplete.
      if (token.length >= 2) {
        const prefixWeight = isLast ? 0.85 : 0.55;
        let found = 0;
        for (const word of this.vocabulary) {
          if (word.length > token.length && word.startsWith(token)) {
            expansions.push([word, prefixWeight]);
            if (++found >= 40) break;
          }
        }
      }
      // Typos: compare what was typed with the words as written on the pages.
      const typed = surfaceQuery[position];
      if (typed.length >= 4 && !this.index.has(token)) {
        const maxDistance = typed.length >= 8 ? 2 : 1;
        let found = 0;
        for (const s of this.surfaces) {
          if (Math.abs(s.length - typed.length) > maxDistance || s[0] !== typed[0]) continue;
          if (editDistance(s, typed, maxDistance) > maxDistance) continue;
          const st = this.surfaceToStem.get(s);
          if (st) expansions.push([st, 0.6]);
          if (++found >= 12) break;
        }
      }
      for (const synonym of this.synonyms.get(token) ?? []) if (synonym !== token) expansions.push([synonym, 0.65]);

      const bestForDoc = new Map<number, number>();
      for (const [word, factor] of expansions) {
        const postings = this.index.get(word);
        if (!postings) continue;
        const weight = (this.idf.get(word) ?? 1) * factor;
        for (const p of postings) {
          const s = p.weight * weight;
          if (s > (bestForDoc.get(p.doc) ?? 0)) bestForDoc.set(p.doc, s);
          let set = matched.get(p.doc);
          if (!set) matched.set(p.doc, (set = new Set()));
          set.add(word);
        }
      }
      for (const [doc, s] of bestForDoc) {
        scores.set(doc, (scores.get(doc) ?? 0) + s);
        coverage.set(doc, (coverage.get(doc) ?? 0) + 1);
      }
    });

    const normalizedQuery = tokens.join(" ");
    const hits: Hit[] = [];
    for (const [doc, score] of scores) {
      const covered = (coverage.get(doc) ?? 0) / tokens.length;
      let s = score * covered * covered;
      const titleTokens = tokenize(this.docs[doc].title).join(" ");
      if (titleTokens === normalizedQuery) s *= 3;
      else if (titleTokens.startsWith(normalizedQuery)) s *= 1.8;
      const { kind, id } = this.docs[doc];
      hits.push({ key: `${kind}:${id}`, kind, itemId: id, score: s, matched: matched.get(doc) ?? new Set() });
    }
    return hits.sort((a, b) => b.score - a.score).slice(0, limit);
  }
}

const engines = new WeakMap<Store, SearchEngine>();

/** One index per loaded library, built on first use. */
export function engineFor(store: Store): SearchEngine {
  let engine = engines.get(store);
  if (!engine) engines.set(store, (engine = new SearchEngine(store)));
  return engine;
}
