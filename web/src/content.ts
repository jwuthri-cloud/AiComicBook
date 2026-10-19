// Mirrors public/content/content.json written by app/tools/build_content.py --web (same shape as the iOS app).
import { createContext, useContext } from "react";

export interface Panel { number: number; heading: string; body: string; code?: string }
export interface Deeper { panels: string[]; further?: string }
export interface NarrationClip { panel: number | null; audio: string; duration: number }
export interface Page {
  id: string; bookId: string; number: number; title: string; printedTitle?: string; subtitle: string;
  panels: Panel[]; footer: string; wordKey: string; summary: string; keywords: string[];
  image: string; thumb: string; video?: string; poster?: string; duration?: number;
  narration?: NarrationClip[]; voice?: string; deeper?: Deeper;
}
export interface Book {
  id: string; collectionId: string; title: string; subtitle: string; objectives: string[];
  cover: string; coverImage: string; hasVideo: boolean; pages: Page[];
}
export interface Collection {
  id: string; title: string; subtitle: string; description: string; symbol: string; tint: string; pageCount: number; books: Book[];
}
export interface Term {
  id: string; term: string; aka: string[]; category: string; short: string; definition: string; advanced?: string;
  related: string[]; pages: string[];
}
export interface Question { id: string; pageId: string; prompt: string; options: string[]; answer: number; explanation: string; difficulty: number }
export interface Tool { id: string; name: string; category: string; what: string; useWhen: string; catch: string; terms: string[] }
export interface TreeNode { step: string; how?: string | null; tool?: string | null; outcome?: string | null; branches?: Branch[] }
export interface Branch { if: string; then: TreeNode[] }
export interface Experiment {
  id: string; theme: string; question: string; chain: string; tree: TreeNode[]; confound: string; success: string; example: string; fellowship?: string | null;
}
export interface Playbook { recipe: string[]; tools: Tool[]; experiments: Experiment[] }

export interface ContentFile {
  version: number; collections: Collection[]; glossary: Term[]; synonyms?: Record<string, string[]>; quiz?: Question[]; playbook?: Playbook;
}

/** The loaded library plus lookup tables (the web twin of ContentStore.swift). */
export class Store {
  collections: Collection[];
  glossary: Term[];
  synonyms: Record<string, string[]>;
  quiz: Question[];
  playbook?: Playbook;
  books = new Map<string, Book>();
  pages = new Map<string, Page>();
  terms = new Map<string, Term>();
  collectionsById = new Map<string, Collection>();
  tools = new Map<string, Tool>();
  matcher: TermMatcher;

  constructor(file: ContentFile) {
    this.collections = file.collections;
    this.glossary = [...file.glossary].sort((a, b) => a.term.localeCompare(b.term, undefined, { sensitivity: "base" }));
    this.synonyms = file.synonyms ?? {};
    this.quiz = file.quiz ?? [];
    this.playbook = file.playbook;
    for (const c of this.collections) {
      this.collectionsById.set(c.id, c);
      for (const b of c.books) {
        this.books.set(b.id, b);
        for (const p of b.pages) this.pages.set(p.id, p);
      }
    }
    for (const t of this.glossary) this.terms.set(t.id, t);
    for (const t of this.playbook?.tools ?? []) this.tools.set(t.id, t);
    this.matcher = new TermMatcher(this.glossary);
  }

  get allBooks() { return this.collections.flatMap((c) => c.books); }
  get videoBooks() { return this.allBooks.filter((b) => b.hasVideo); }
  bookFor(page: Page) { return this.books.get(page.bookId); }
  collectionFor(book: Book) { return this.collectionsById.get(book.collectionId); }

  /** Git and data-structure words read as plain English outside their own collections. */
  termsToSkip(book: Book): Set<string> {
    const scoped: Record<string, string[]> = { Git: ["swe"], Algorithms: ["leetcode", "ml"], "Data Structures": ["leetcode", "ml"] };
    return new Set(this.glossary.filter((t) => scoped[t.category] && !scoped[t.category].includes(book.collectionId)).map((t) => t.id));
  }

  get termOfTheDay(): Term | undefined {
    if (!this.glossary.length) return undefined;
    const day = Math.floor(Date.now() / 86_400_000);
    return this.glossary[day % this.glossary.length];
  }

  experimentsUsing(toolId: string): Experiment[] {
    const uses = (nodes: TreeNode[]): boolean => nodes.some((n) => n.tool === toolId || (n.branches ?? []).some((b) => uses(b.then)));
    return (this.playbook?.experiments ?? []).filter((e) => uses(e.tree));
  }
}

export const url = (relative: string) => `/content/${relative}`;

// ---------- glossary term matching (port of TermMatcher.swift) ----------

export interface TermMatch { start: number; end: number; termId: string }

export class TermMatcher {
  private lookup = new Map<string, string>();
  private sensitive?: RegExp;
  private insensitive?: RegExp;

  constructor(terms: Term[]) {
    const sens: string[] = [];
    const insens: string[] = [];
    for (const term of terms) {
      const names = new Set(
        [term.term, ...term.aka].map((n) => n.replace(/\s*\(.*?\)/g, "").trim()).filter((n) => n.length >= 2),
      );
      for (const name of names) {
        this.lookup.set(TermMatcher.key(name), term.id);
        const pattern = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/ /g, "[\\s-]+");
        (name === name.toUpperCase() && name.length <= 6 ? sens : insens).push(pattern);
      }
    }
    const build = (patterns: string[], flags: string) =>
      patterns.length ? new RegExp(`(?<![\\w-])(?:${patterns.sort((a, b) => b.length - a.length).join("|")})(?:s|es)?(?![\\w-])`, flags) : undefined;
    this.sensitive = build(sens, "g");
    this.insensitive = build(insens, "gi");
  }

  static key(s: string) { return s.toLowerCase().replace(/-/g, " ").split(/\s+/).filter(Boolean).join(" "); }

  private idFor(matched: string): string | undefined {
    const k = TermMatcher.key(matched);
    const hit = this.lookup.get(k);
    if (hit) return hit;
    for (const suffix of ["es", "s"]) if (k.endsWith(suffix)) { const id = this.lookup.get(k.slice(0, -suffix.length)); if (id) return id; }
    return undefined;
  }

  /** Each term once per `seen` set, longest match wins, no overlaps. */
  matches(text: string, seen: Set<string>, exclude: Set<string> = new Set()): TermMatch[] {
    const candidates: { start: number; end: number; text: string }[] = [];
    for (const re of [this.insensitive, this.sensitive]) {
      if (!re) continue;
      re.lastIndex = 0;
      for (const m of text.matchAll(re)) candidates.push({ start: m.index!, end: m.index! + m[0].length, text: m[0] });
    }
    candidates.sort((a, b) => (b.end - b.start) - (a.end - a.start) || a.start - b.start);
    const taken: TermMatch[] = [];
    for (const c of candidates) {
      if (taken.some((t) => c.start < t.end && t.start < c.end)) continue;
      const id = this.idFor(c.text);
      if (!id || seen.has(id) || exclude.has(id)) continue;
      seen.add(id);
      taken.push({ start: c.start, end: c.end, termId: id });
    }
    return taken.sort((a, b) => a.start - b.start);
  }
}

export const StoreContext = createContext<Store | null>(null);

export function useStore(): Store {
  const store = useContext(StoreContext);
  if (!store) throw new Error("useStore outside the content provider");
  return store;
}

export async function loadStore(): Promise<Store> {
  const res = await fetch(url("content.json"));
  if (!res.ok) throw new Error(`content.json: ${res.status}`);
  return new Store(await res.json());
}
