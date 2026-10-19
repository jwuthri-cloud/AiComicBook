// Finds library pages relevant to a question, for the assistant's context. A compact port of the lexical
// part of SearchEngine.swift (weighted fields, saturating term frequency, idf, prefix and glossary-synonym
// expansion, coverage). Pages only; no typo tolerance or on-device embeddings.
import type { Store } from "../../content";

const STOP = new Set([
  "a", "an", "the", "and", "or", "of", "to", "in", "on", "for", "is", "are", "it", "its", "be", "by", "as",
  "at", "this", "that", "with", "from", "can", "do", "does", "what", "how", "why", "when", "who", "which",
  "about", "into", "than", "then", "there", "their", "they", "them", "you", "your", "we", "our", "i", "me",
  "my", "so", "if", "not", "but", "was", "were", "has", "have", "had", "will", "would", "should", "could",
]);

const surfaceWords = (text: string) =>
  text.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);

function stem(w: string): string {
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

const tokenize = (text: string) => surfaceWords(text).map(stem).filter((t) => t && !STOP.has(t));

interface Posting { doc: number; weight: number }
interface Index {
  ids: string[];
  titles: string[];
  postings: Map<string, Posting[]>;
  idf: Map<string, number>;
  vocabulary: string[];
  synonyms: Map<string, string[]>;
}

const cache = new WeakMap<Store, Index>();

function build(store: Store): Index {
  const ids: string[] = [];
  const titles: string[] = [];
  const postings = new Map<string, Posting[]>();
  for (const book of store.allBooks) {
    for (const page of book.pages) {
      const doc = ids.length;
      ids.push(page.id);
      titles.push(page.title);
      const fields: [string, number][] = [
        [page.title, 6], [page.printedTitle ?? "", 3], [page.subtitle, 3], [page.keywords.join(" "), 4],
        [page.footer, 1.5], [page.summary, 1], [book.title, 1], [page.wordKey, 1],
      ];
      for (const panel of page.panels) {
        fields.push([panel.heading, 2.5], [panel.body, 1]);
        if (panel.code) fields.push([panel.code, 0.5]);
      }
      const weights = new Map<string, number>();
      for (const [text, weight] of fields) {
        for (const token of tokenize(text)) {
          // Saturating term frequency: repeated words help a little, not linearly.
          weights.set(token, Math.min((weights.get(token) ?? 0) + weight, weight * 2.2));
        }
      }
      for (const [token, weight] of weights) {
        const list = postings.get(token);
        if (list) list.push({ doc, weight });
        else postings.set(token, [{ doc, weight }]);
      }
    }
  }
  const n = ids.length;
  const idf = new Map<string, number>();
  for (const [token, list] of postings) {
    const df = list.length;
    idf.set(token, Math.log(1 + (n - df + 0.5) / (df + 0.5)));
  }
  // Acronym <-> expansion, so "rlhf" also finds "reinforcement learning from human feedback".
  const synonyms = new Map<string, string[]>();
  const addSynonyms = (key: string, words: string[]) => synonyms.set(key, [...(synonyms.get(key) ?? []), ...words]);
  for (const term of store.glossary) {
    const sets = [term.term, ...term.aka].map(tokenize).filter((t) => t.length);
    for (const tokens of sets) {
      if (tokens.length !== 1) continue;
      const others = sets.filter((s) => s.join(" ") !== tokens.join(" ")).flat();
      if (others.length) addSynonyms(tokens[0], others);
    }
  }
  for (const [word, phrases] of Object.entries(store.synonyms)) {
    const key = tokenize(word).join(" ");
    if (key) addSynonyms(key, phrases.flatMap(tokenize));
  }
  return { ids, titles, postings, idf, vocabulary: [...postings.keys()], synonyms };
}

/** Page ids ranked by relevance to `query`, best first. */
export function searchPages(store: Store, query: string, limit = 20): string[] {
  const index = cache.get(store) ?? build(store);
  cache.set(store, index);
  const tokens = tokenize(query);
  if (!tokens.length) return [];

  const scores = new Map<number, number>();
  const coverage = new Map<number, number>();
  tokens.forEach((token, position) => {
    const isLast = position === tokens.length - 1;
    const expansions: [string, number][] = [[token, 1]];
    if (token.length >= 2) {
      const prefixWeight = isLast ? 0.85 : 0.55;
      let added = 0;
      for (const word of index.vocabulary) {
        if (word.length > token.length && word.startsWith(token)) {
          expansions.push([word, prefixWeight]);
          if (++added >= 40) break;
        }
      }
    }
    for (const synonym of index.synonyms.get(token) ?? []) if (synonym !== token) expansions.push([synonym, 0.65]);

    const best = new Map<number, number>();
    for (const [word, factor] of expansions) {
      const list = index.postings.get(word);
      if (!list) continue;
      const weight = (index.idf.get(word) ?? 1) * factor;
      for (const p of list) {
        const s = p.weight * weight;
        if (s > (best.get(p.doc) ?? 0)) best.set(p.doc, s);
      }
    }
    for (const [doc, s] of best) {
      scores.set(doc, (scores.get(doc) ?? 0) + s);
      coverage.set(doc, (coverage.get(doc) ?? 0) + 1);
    }
  });

  const normalized = tokens.join(" ");
  return [...scores]
    .map(([doc, score]) => {
      const covered = (coverage.get(doc) ?? 0) / tokens.length;
      let s = score * covered * covered;
      const title = tokenize(index.titles[doc]).join(" ");
      if (title === normalized) s *= 3;
      else if (title.startsWith(normalized)) s *= 1.8;
      return { id: index.ids[doc], s };
    })
    .sort((a, b) => b.s - a.s)
    .slice(0, limit)
    .map((h) => h.id);
}
