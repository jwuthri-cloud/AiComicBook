// Per-device state in localStorage (reading progress, bookmarks, settings). Every hook re-renders when any
// component writes the same key, so the whole app stays in sync without a global store.
import { useCallback, useSyncExternalStore } from "react";
import type { Book, Page } from "./content";

const EVENT = "atlas-storage";

function read<T>(key: string, fallback: T): T {
  try {
    const raw = localStorage.getItem(key);
    return raw === null ? fallback : (JSON.parse(raw) as T);
  } catch {
    return fallback;
  }
}

export function write<T>(key: string, value: T) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
  } catch {
    /* private mode or full storage: keep going without persistence */
  }
  window.dispatchEvent(new CustomEvent(EVENT, { detail: key }));
}

const cache = new Map<string, { raw: string | null; value: unknown }>();

/** useState backed by localStorage, shared by every component using the same key. */
export function useLocal<T>(key: string, fallback: T): [T, (v: T | ((old: T) => T)) => void] {
  const subscribe = useCallback((notify: () => void) => {
    const on = (e: Event) => {
      if (e instanceof StorageEvent ? e.key === key : (e as CustomEvent).detail === key) notify();
    };
    window.addEventListener(EVENT, on);
    window.addEventListener("storage", on);
    return () => {
      window.removeEventListener(EVENT, on);
      window.removeEventListener("storage", on);
    };
  }, [key]);
  const snapshot = () => {
    let raw: string | null = null;
    try { raw = localStorage.getItem(key); } catch { /* ignore */ }
    const hit = cache.get(key);
    if (hit && hit.raw === raw) return hit.value as T;
    const value = raw === null ? fallback : read(key, fallback);
    cache.set(key, { raw, value });
    return value;
  };
  const value = useSyncExternalStore(subscribe, snapshot, () => fallback);
  const set = useCallback((v: T | ((old: T) => T)) => {
    const next = typeof v === "function" ? (v as (old: T) => T)(read(key, fallback)) : v;
    write(key, next);
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  return [value, set];
}

// ---------- settings ----------

export type Appearance = "system" | "light" | "dark";
export const useAppearance = () => useLocal<Appearance>("appearance", "system");
export const useAdvanced = () => useLocal<boolean>("advancedMode", false);
export const useTextScale = () => useLocal<number>("textScale", 1);
export type ReaderMode = "comic" | "text" | "video";
export const useReaderMode = () => useLocal<ReaderMode>("readerMode", "text");

// ---------- library progress (port of LibraryState.swift) ----------

interface Library {
  lastPage: Record<string, number>;
  readPages: string[];
  bookmarks: string[];
  recentBooks: string[];
  recentSearches: string[];
}
const empty: Library = { lastPage: {}, readPages: [], bookmarks: [], recentBooks: [], recentSearches: [] };

export function useLibrary() {
  const [lib, setLib] = useLocal<Library>("library.v1", empty);
  return {
    lib,
    lastPageIndex: (book: Book) => Math.min(lib.lastPage[book.id] ?? 0, Math.max(book.pages.length - 1, 0)),
    open: (book: Book, index: number) =>
      setLib((l) => ({
        ...l,
        lastPage: { ...l.lastPage, [book.id]: index },
        readPages: l.readPages.includes(book.pages[index]?.id) ? l.readPages : [...l.readPages, book.pages[index].id],
        recentBooks: [book.id, ...l.recentBooks.filter((b) => b !== book.id)].slice(0, 12),
      })),
    isRead: (page: Page) => lib.readPages.includes(page.id),
    progress: (book: Book) => (book.pages.length ? book.pages.filter((p) => lib.readPages.includes(p.id)).length / book.pages.length : 0),
    isBookmarked: (page: Page) => lib.bookmarks.includes(page.id),
    toggleBookmark: (page: Page) =>
      setLib((l) => ({ ...l, bookmarks: l.bookmarks.includes(page.id) ? l.bookmarks.filter((b) => b !== page.id) : [page.id, ...l.bookmarks] })),
    remember: (search: string) => {
      const q = search.trim();
      if (q.length < 2) return;
      setLib((l) => ({ ...l, recentSearches: [q, ...l.recentSearches.filter((s) => s.toLowerCase() !== q.toLowerCase())].slice(0, 8) }));
    },
    clearSearches: () => setLib((l) => ({ ...l, recentSearches: [] })),
  };
}
