// What the assistant knows: system prompt, page digests and the message list sent to OpenAI
// (port of AssistantSession's prompt section in Assistant.swift).
import type { Page, Store, Term } from "../../content";
import type { AskContext } from ".";
import type { ApiMessage, ContentPart } from "./openai";
import { searchPages } from "./retrieve";

export type Source = { kind: "page" | "term"; id: string };

export interface ChatMessage {
  id: number;
  role: "user" | "assistant";
  text: string;
  /** JPEG data URL of an attached photo. */
  image?: string;
  sources: Source[];
  failed?: boolean;
}

export const contextId = (c: AskContext) =>
  c.kind === "page" ? `page:${c.pageId}:${!!c.showingComic}` : c.kind === "term" ? `term:${c.termId}` : "library";

export function suggestions(c: AskContext): string[] {
  switch (c.kind) {
    case "library":
      return ["What should I read first?", "Explain AI alignment in two minutes", "How do the fellowship projects connect?", "Quiz me on something random"];
    case "page":
      return ["Explain this page like I'm 12", "Give me another analogy", "What's the key caveat here?", "Ask me 3 questions about it"];
    case "term":
      return ["Give me an everyday example", "How is it different from related terms?", "Where does this show up in practice?"];
  }
}

/** Up to four other pages that look relevant to the question. Canned prompts about the open page or word
 * ("Explain it simpler", suggestions) skip the search: their wording would only match unrelated pages. */
export function relatedPages(store: Store, question: string, c: AskContext, canned = false): Page[] {
  if (canned && c.kind !== "library") return [];
  const current = c.kind === "page" ? c.pageId : undefined;
  return searchPages(store, question, 20)
    .filter((id) => id !== current)
    .slice(0, 4)
    .map((id) => store.pages.get(id))
    .filter((p): p is Page => !!p);
}

/** Glossary words named in the question (besides the one being looked at). */
export function mentionedTerms(store: Store, question: string, c: AskContext): Term[] {
  const exclude = new Set(c.kind === "term" ? [c.termId] : []);
  return store.matcher
    .matches(question, new Set(), exclude)
    .slice(0, 3)
    .map((m) => store.terms.get(m.termId))
    .filter((t): t is Term => !!t);
}

export function sourcesFor(c: AskContext, related: Page[], terms: Term[]): Source[] {
  const result: Source[] = [];
  if (c.kind === "page") result.push({ kind: "page", id: c.pageId });
  if (c.kind === "term") result.push({ kind: "term", id: c.termId });
  return [...result, ...related.map((p) => ({ kind: "page" as const, id: p.id })), ...terms.map((t) => ({ kind: "term" as const, id: t.id }))];
}

export function pageDigest(page: Page, store: Store, limit: number): string {
  const book = store.bookFor(page);
  const lines = [`# ${page.title}` + (book ? ` (from “${book.title}”)` : "")];
  if (page.subtitle) lines.push(page.subtitle);
  if (page.wordKey) lines.push(`Word key: ${page.wordKey}`);
  for (const panel of page.panels) lines.push(`${panel.number}. ${panel.heading}: ${panel.body}` + (panel.code ? `\n${panel.code}` : ""));
  if (page.footer) lines.push(`Takeaway: ${page.footer}`);
  const text = lines.join("\n");
  return text.length > limit ? text.slice(0, limit) + "…" : text;
}

export function systemPrompt(store: Store, c: AskContext): string {
  const library = store.collections.map((col) => `- ${col.title}: ` + col.books.map((b) => b.title).join("; ")).join("\n");
  let prompt = `You are the study companion inside Safety Atlas, a library of illustrated comic study guides (this is its website). The reader is a curious learner, often reading on a train or at the gym on a phone.

How to answer:
- Plain, friendly language; short paragraphs; use an everyday analogy when it helps. Define jargon in the same sentence.
- Keep answers phone-sized (usually under 180 words) unless asked for more. Light Markdown only (bold, italics, short lists).
- Stay accurate. Say when something is uncertain or beyond the material. Never invent results, numbers or citations.
- Fellowship books describe PROPOSED research: never present their experiments as completed. Probes and monitors are imperfect measurements, not mind readers; don't attribute feelings or intentions to models.
- When you rely on a page, mention its title in bold so the reader can find it.
- If asked to quiz, ask one question at a time and wait for the answer.

The library:
${library}`;
  if (c.kind === "library") {
    prompt += "\n\nThe reader is on the home screen; help them choose what to learn and answer questions about anything in the library.";
  } else if (c.kind === "page") {
    const page = store.pages.get(c.pageId);
    if (page) {
      const book = store.bookFor(page);
      prompt += `\n\nThe reader is on page ${page.number} of ${book?.pages.length ?? 0} of the book “${book?.title ?? ""}”.`;
      if (book?.objectives.length) prompt += " The book's goals: " + book.objectives.join(" ");
      prompt += "\n\nCurrent page:\n" + pageDigest(page, store, 4000);
      if (c.showingComic) prompt += "\n\nThey are looking at the comic version; its image is attached to their first message.";
    }
  } else {
    const term = store.terms.get(c.termId);
    if (term) {
      prompt += `\n\nThe reader is looking at the glossary entry “${term.term}”${term.aka.length ? ` (also: ${term.aka.join(", ")})` : ""}: ${term.definition}`;
    }
  }
  return prompt;
}

/** System prompt + conversation. `history` ends with the newest user message (the empty reply excluded). */
export function buildMessages(
  store: Store, c: AskContext, history: ChatMessage[], related: Page[], terms: Term[], comicImage?: string,
): ApiMessage[] {
  const result: ApiMessage[] = [{ role: "system", content: systemPrompt(store, c) }];
  history.forEach((message, i) => {
    if (message.role === "assistant") {
      if (!message.failed && message.text) result.push({ role: "assistant", content: message.text });
      return;
    }
    let text = message.text || "What is in this image?";
    // The newest question carries the library excerpts found for it.
    if (i === history.length - 1) {
      if (related.length) {
        text += "\n\n---\nPossibly relevant pages from the library (use them if they help, cite their titles):\n" +
          related.map((p) => pageDigest(p, store, 1400)).join("\n\n");
      }
      if (terms.length) {
        text += "\n\n---\nGlossary entries named in the question:\n" +
          terms.map((t) => `- ${t.term}${t.aka.length ? ` (${t.aka.join(", ")})` : ""}: ${t.short || t.definition}`).join("\n");
      }
    }
    const parts: ContentPart[] = [{ type: "text", text }];
    if (message.image) parts.push({ type: "image_url", image_url: { url: message.image } });
    // Asked from the comic view: the page image rides along with the first question of the chat.
    if (i === 0 && comicImage) parts.push({ type: "image_url", image_url: { url: comicImage } });
    result.push({ role: "user", content: parts });
  });
  return result;
}
