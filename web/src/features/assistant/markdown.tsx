// Just enough Markdown for assistant replies: paragraphs, headings (as bold lines), bullet and numbered
// lists, fenced code, inline code, bold, italics and http(s) links. No HTML is ever injected.
import type { ReactNode } from "react";

const INLINE = /(`[^`\n]+`)|(\*\*[^*\n]+?\*\*)|(__[^_\n]+?__)|(\*[^*\s][^*\n]*?\*)|((?<![\w])_[^_\s][^_\n]*?_(?![\w]))|(\[[^\]\n]+\]\(https?:\/\/[^)\s]+\))/g;

function inline(text: string, keyPrefix = ""): ReactNode[] {
  const out: ReactNode[] = [];
  let at = 0;
  let n = 0;
  for (const m of text.matchAll(INLINE)) {
    const start = m.index ?? 0;
    if (start > at) out.push(text.slice(at, start));
    const token = m[0];
    const key = `${keyPrefix}${n++}`;
    if (m[1]) out.push(<code key={key}>{token.slice(1, -1)}</code>);
    else if (m[2] || m[3]) out.push(<strong key={key}>{inline(token.slice(2, -2), key + "-")}</strong>);
    else if (m[4] || m[5]) out.push(<em key={key}>{inline(token.slice(1, -1), key + "-")}</em>);
    else {
      const close = token.indexOf("](");
      out.push(<a key={key} href={token.slice(close + 2, -1)} target="_blank" rel="noopener noreferrer">{token.slice(1, close)}</a>);
    }
    at = start + token.length;
  }
  if (at < text.length) out.push(text.slice(at));
  return out;
}

/** Lines joined with <br>, each with inline formatting. */
function lines(list: string[], key: string): ReactNode[] {
  return list.flatMap((l, i) => (i ? [<br key={`${key}br${i}`} />, ...inline(l, `${key}l${i}-`)] : inline(l, `${key}l${i}-`)));
}

type Block =
  | { kind: "p"; lines: string[] }
  | { kind: "h"; text: string }
  | { kind: "code"; text: string }
  | { kind: "ul" | "ol"; items: string[][]; start: number };

function parse(src: string): Block[] {
  const blocks: Block[] = [];
  const rows = src.replace(/\r\n?/g, "\n").split("\n");
  let i = 0;
  while (i < rows.length) {
    const row = rows[i];
    if (/^\s*```/.test(row)) {
      const body: string[] = [];
      i++;
      while (i < rows.length && !/^\s*```/.test(rows[i])) body.push(rows[i++]);
      i++; // closing fence (absent while streaming)
      blocks.push({ kind: "code", text: body.join("\n") });
      continue;
    }
    if (!row.trim()) { i++; continue; }
    const heading = row.match(/^\s*#{1,6}\s+(.*)$/);
    if (heading) { blocks.push({ kind: "h", text: heading[1] }); i++; continue; }
    const bullet = /^\s*[-*•+]\s+/;
    const numbered = /^\s*(\d+)[.)]\s+/;
    if (bullet.test(row) || numbered.test(row)) {
      const ordered = numbered.test(row);
      const marker = ordered ? numbered : bullet;
      const block: Block = { kind: ordered ? "ol" : "ul", items: [], start: ordered ? Number(row.match(numbered)![1]) : 1 };
      while (i < rows.length) {
        const r = rows[i];
        if (marker.test(r)) block.items.push([r.replace(marker, "")]);
        else if (r.trim() && /^\s{2,}\S/.test(r) && block.items.length) block.items[block.items.length - 1].push(r.trim());
        else break;
        i++;
      }
      blocks.push(block);
      continue;
    }
    const para: string[] = [];
    while (i < rows.length && rows[i].trim() && !/^\s*(```|#{1,6}\s|[-*•+]\s|\d+[.)]\s)/.test(rows[i])) para.push(rows[i++]);
    if (!para.length) para.push(rows[i++]);
    blocks.push({ kind: "p", lines: para });
  }
  return blocks;
}

export function Markdown({ text }: { text: string }) {
  return (
    <div className="md">
      {parse(text).map((b, i) => {
        const key = `b${i}`;
        switch (b.kind) {
          case "p": return <p key={key}>{lines(b.lines, key)}</p>;
          case "h": return <p key={key} className="md-h"><strong>{inline(b.text, key)}</strong></p>;
          case "code": return <pre key={key}><code>{b.text}</code></pre>;
          case "ul": return <ul key={key}>{b.items.map((it, j) => <li key={j}>{lines(it, `${key}i${j}`)}</li>)}</ul>;
          case "ol": return <ol key={key} start={b.start}>{b.items.map((it, j) => <li key={j}>{lines(it, `${key}i${j}`)}</li>)}</ol>;
        }
      })}
    </div>
  );
}
