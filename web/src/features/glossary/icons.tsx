// A few glossary-only glyphs missing from the shared Icon set; everything else falls through to it.
import type { ReactNode } from "react";
import { Icon } from "../../ui";

const EXTRA: Record<string, ReactNode> = {
  bubble: <path d="M4 5h16v11H9l-5 4z" />,
  shuffle: <><path d="M3 7h3c4 0 6 10 10 10h4" /><path d="M3 17h3c1.6 0 2.8-1.6 3.9-3.6M13.1 9.6C14.2 7.6 15.4 7 17 7h3" /><path d="m17 4 3 3-3 3M17 14l3 3-3 3" /></>,
  undo: <><path d="M9 14 4 9l5-5" /><path d="M4 9h11a5 5 0 0 1 0 10h-3" /></>,
};

export function GIcon({ name, size = 18 }: { name: string; size?: number }) {
  const p = EXTRA[name];
  if (!p) return <Icon name={name} size={size} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {p}
    </svg>
  );
}
