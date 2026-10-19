// Playback engine for Listen mode (port of Listener.swift). Plays a page's pre-recorded narration clips
// one after the other (one clip per panel, plus title and takeaway), falling back to the browser's speech
// synthesis when a page has no narration or a clip fails to load. Framework-free; the provider subscribes.
import { type Book, type Page, url } from "../../content";

/** Same speeds as the app. */
export const SPEEDS = [0.8, 1, 1.2, 1.4, 1.7] as const;

/** One spoken chunk of a page; `panel` is the panel being read (null for title and takeaway). */
interface Segment {
  text: string;
  panel: number | null;
  audio?: string;
}

export interface ListenState {
  book?: Book;
  pageIndex: number;
  panel: number | null;
  isPlaying: boolean;
  /** 0...1 through the current page. */
  pageProgress: number;
}

const hasSpeech = () => typeof window !== "undefined" && "speechSynthesis" in window;
const hasMediaSession = () => typeof navigator !== "undefined" && "mediaSession" in navigator;

export class ListenEngine {
  state: ListenState = { pageIndex: 0, panel: null, isPlaying: false, pageProgress: 0 };
  speed = 1;

  private listeners = new Set<() => void>();
  private audio?: HTMLAudioElement;
  private segments: Segment[] = [];
  private segmentIndex = 0;
  /** Bumped whenever playback restarts, so callbacks from a stopped clip or utterance are ignored. */
  private generation = 0;
  private clipToken = -1;
  private utterance?: SpeechSynthesisUtterance;
  private timer?: number;
  /** The current segment ended and the short breath before the next one is running. */
  private finished = false;
  private metaKey = "";

  subscribe = (fn: () => void) => {
    this.listeners.add(fn);
    return () => { this.listeners.delete(fn); };
  };

  getState = () => this.state;

  get page(): Page | undefined {
    return this.state.book?.pages[this.state.pageIndex];
  }

  private set(patch: Partial<ListenState>) {
    this.state = { ...this.state, ...patch };
    this.updateMediaSession();
    for (const fn of this.listeners) fn();
  }

  // MARK: Transport

  start(book: Book, index: number) {
    this.stopSpeech();
    this.state = { ...this.state, book };
    this.setUpRemoteCommands();
    this.load(index);
    this.set({ isPlaying: true });
    this.speakCurrent();
  }

  toggle = () => (this.state.isPlaying ? this.pause() : this.resume());

  pause = () => {
    if (!this.state.book) return;
    this.audio?.pause();
    // Browser speech pause/resume is unreliable (Android ignores it, Chrome drops long pauses):
    // cancel now and re-read the current panel on resume.
    if (this.utterance) {
      this.utterance = undefined;
      window.speechSynthesis.cancel();
    }
    this.set({ isPlaying: false });
  };

  resume = () => {
    if (!this.state.book) return;
    this.set({ isPlaying: true });
    if (this.finished) return this.advance();
    if (this.segmentIndex >= this.segments.length) return this.jump(this.state.pageIndex); // replay the last page
    const segment = this.segments[this.segmentIndex];
    const a = this.audio;
    if (segment.audio && a && this.clipToken === this.generation && !a.ended && a.currentTime > 0) {
      a.playbackRate = this.speed;
      a.play().catch(() => this.speakCurrent());
    } else {
      this.speakCurrent();
    }
  };

  next = () => {
    const { book, pageIndex } = this.state;
    if (book && pageIndex + 1 < book.pages.length) this.jump(pageIndex + 1);
  };

  /** Like a music player: back to the start of the page first, then the previous page. */
  previous = () => {
    const { pageIndex } = this.state;
    this.jump(this.segmentIndex > 1 || pageIndex === 0 ? pageIndex : pageIndex - 1);
  };

  jump = (index: number) => {
    const book = this.state.book;
    if (!book || index < 0 || index >= book.pages.length) return;
    this.stopSpeech();
    this.load(index);
    this.set({ isPlaying: true });
    this.speakCurrent();
  };

  stop = () => {
    this.stopSpeech();
    this.segments = [];
    this.set({ book: undefined, panel: null, isPlaying: false, pageProgress: 0 });
    this.tearDownRemoteCommands();
  };

  /** Clips change rate immediately; speech restarts the current panel at the new rate. */
  setSpeed(value: number) {
    this.speed = value;
    if (this.audio) this.audio.playbackRate = value;
    if (this.utterance && this.state.isPlaying) {
      this.stopSpeech();
      this.speakCurrent();
    }
  }

  // MARK: Internals

  private stopSpeech() {
    this.generation += 1;
    this.finished = false;
    window.clearTimeout(this.timer);
    if (this.utterance || (hasSpeech() && window.speechSynthesis.speaking)) {
      this.utterance = undefined;
      window.speechSynthesis.cancel();
    }
    this.audio?.pause();
  }

  private load(index: number) {
    const book = this.state.book;
    if (!book) return;
    const page = book.pages[index];
    this.segments = page.narration?.length
      ? page.narration.map((c) => ({ text: "", panel: c.panel, audio: c.audio }))
      : speechSegments(page);
    this.segmentIndex = 0;
    this.finished = false;
    this.set({ pageIndex: index, panel: null, pageProgress: 0 });
  }

  private ensureAudio(): HTMLAudioElement {
    if (this.audio) return this.audio;
    // One element reused for every clip, so the first user tap keeps unlocking playback on iOS.
    const a = new Audio();
    a.preload = "auto";
    a.addEventListener("ended", () => {
      if (this.clipToken === this.generation) this.finishSegment();
    });
    a.addEventListener("error", () => {
      if (this.clipToken === this.generation && this.state.isPlaying) this.fallbackToSpeech();
    });
    this.audio = a;
    return a;
  }

  private speakCurrent() {
    if (!this.state.isPlaying) return;
    const segment = this.segments[this.segmentIndex];
    if (!segment) return;
    this.finished = false;
    this.set({ panel: segment.panel, pageProgress: this.segmentIndex / Math.max(this.segments.length, 1) });

    if (segment.audio) {
      const a = this.ensureAudio();
      const token = ++this.generation;
      this.clipToken = token;
      a.src = url(segment.audio);
      a.playbackRate = this.speed;
      a.play().catch((error: DOMException) => {
        if (token !== this.generation) return;
        if (error.name === "NotAllowedError") this.set({ isPlaying: false }); // autoplay blocked: wait for a tap
        else if (error.name !== "AbortError") this.fallbackToSpeech();
      });
      return;
    }

    if (!hasSpeech()) return this.finishSegment();
    const u = new SpeechSynthesisUtterance(segment.text);
    const voice = pickVoice();
    if (voice) u.voice = voice;
    u.lang = voice?.lang ?? "en-US";
    u.rate = this.speed;
    u.onend = () => {
      if (u !== this.utterance) return;
      this.utterance = undefined;
      this.finishSegment();
    };
    u.onerror = (e) => {
      if (u !== this.utterance || e.error === "interrupted" || e.error === "canceled") return;
      this.utterance = undefined;
      if (e.error === "not-allowed") this.set({ isPlaying: false });
      else this.finishSegment();
    };
    this.utterance = u;
    window.speechSynthesis.speak(u);
  }

  /** A clip could not be played: read this page with the browser voice from the same panel on. */
  private fallbackToSpeech() {
    const page = this.page;
    if (!page) return;
    const failed = this.segments[this.segmentIndex];
    const segments = speechSegments(page);
    let index = segments.findIndex((s) => s.panel === (failed?.panel ?? null));
    if (failed?.panel == null && this.segmentIndex > 0) index = segments.length - 1; // the takeaway clip
    this.generation += 1;
    this.segments = segments;
    this.segmentIndex = Math.max(0, index);
    this.speakCurrent();
  }

  /** A short breath between panels, a longer one between pages. */
  private finishSegment() {
    this.finished = true;
    const last = this.segmentIndex === this.segments.length - 1;
    // Timers are throttled in background tabs and on a locked phone: move on right away there.
    if (typeof document !== "undefined" && document.hidden) return this.advance();
    const pause = (last ? 0.8 : 0.3) / Math.max(this.speed, 0.5);
    const token = this.generation;
    window.clearTimeout(this.timer);
    this.timer = window.setTimeout(() => {
      if (token === this.generation && this.state.isPlaying && this.finished) this.advance();
    }, pause * 1000);
  }

  private advance() {
    this.finished = false;
    this.segmentIndex += 1;
    const { book, pageIndex } = this.state;
    if (this.segmentIndex < this.segments.length) {
      this.speakCurrent();
    } else if (book && pageIndex + 1 < book.pages.length) {
      this.load(pageIndex + 1);
      this.speakCurrent();
    } else {
      // End of the book.
      this.set({ isPlaying: false, panel: null, pageProgress: 1 });
    }
  }

  // MARK: Lock screen (Media Session API)

  private setUpRemoteCommands() {
    if (!hasMediaSession()) return;
    const handlers: [MediaSessionAction, MediaSessionActionHandler][] = [
      ["play", () => this.resume()],
      ["pause", () => this.pause()],
      ["nexttrack", () => this.next()],
      ["previoustrack", () => this.previous()],
      ["stop", () => this.stop()],
    ];
    for (const [action, handler] of handlers) {
      try { navigator.mediaSession.setActionHandler(action, handler); } catch { /* unsupported action */ }
    }
  }

  private tearDownRemoteCommands() {
    if (!hasMediaSession()) return;
    for (const action of ["play", "pause", "nexttrack", "previoustrack", "stop"] as MediaSessionAction[]) {
      try { navigator.mediaSession.setActionHandler(action, null); } catch { /* ignore */ }
    }
    navigator.mediaSession.metadata = null;
    navigator.mediaSession.playbackState = "none";
    this.metaKey = "";
  }

  private updateMediaSession() {
    if (!hasMediaSession()) return;
    const { book, pageIndex, isPlaying } = this.state;
    const page = this.page;
    if (!book || !page) return;
    const key = `${book.id}:${pageIndex}`;
    if (key !== this.metaKey && typeof MediaMetadata !== "undefined") {
      this.metaKey = key;
      navigator.mediaSession.metadata = new MediaMetadata({
        title: page.title,
        artist: book.title,
        album: `Safety Atlas · page ${pageIndex + 1} of ${book.pages.length}`,
        artwork: [{ src: new URL(url(page.thumb), window.location.href).href, type: "image/jpeg" }],
      });
    }
    navigator.mediaSession.playbackState = isPlaying ? "playing" : "paused";
  }
}

// MARK: What gets read when there is no recording

function speechSegments(page: Page): Segment[] {
  const result: Segment[] = [];
  let opening = `Page ${page.number}. ${page.title}.`;
  if (page.subtitle) opening += ` ${sentence(page.subtitle)}`;
  result.push({ text: opening, panel: null });
  if (!page.panels.length) {
    result.push({ text: page.summary || "This page is a picture; open the comic to see it.", panel: null });
  }
  page.panels.forEach((p, i) => {
    let text = sentence(p.heading);
    if (p.body) text += " " + speakable(p.body);
    if (p.code) text += " The page shows a code example here.";
    result.push({ text, panel: i });
  });
  if (page.footer) result.push({ text: "Takeaway: " + sentence(page.footer), panel: null });
  return result;
}

function sentence(s: string): string {
  const t = s.trim();
  return !t || ".!?:".includes(t[t.length - 1]) ? t : t + ".";
}

/** Small fixes so symbols read naturally. */
function speakable(s: string): string {
  return s
    .replaceAll("→", ", then ")
    .replaceAll("->", ", then ")
    .replaceAll("≈", " about ")
    .replaceAll(" vs. ", " versus ")
    .replaceAll(" vs ", " versus ")
    .replaceAll("e.g.", "for example")
    .replaceAll("i.e.", "that is");
}

/** English voices, best quality first (the browser twin of Listener.voices). */
function pickVoice(): SpeechSynthesisVoice | undefined {
  const score = (v: SpeechSynthesisVoice) =>
    (/premium|enhanced|natural|neural/i.test(v.name) ? 4 : 0) +
    (/google|samantha|daniel|karen/i.test(v.name) ? 2 : 0) +
    (/^en[-_]US$/i.test(v.lang) ? 1 : 0) +
    (/novelty|whisper|bells|bubbles|zarvox|trinoids|cellos|bahh|boing|jester|organ|superstar|wobble/i.test(v.name) ? -10 : 0);
  return window.speechSynthesis
    .getVoices()
    .filter((v) => v.lang.toLowerCase().startsWith("en"))
    .sort((a, b) => score(b) - score(a))[0];
}
