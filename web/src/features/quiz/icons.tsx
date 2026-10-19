// Quiz-only icons (same 24px stroke style as Icon in ui.tsx); unknown names fall back to the shared set.
import type { ReactNode } from "react";
import { Icon } from "../../ui";

const PATHS: Record<string, ReactNode> = {
  target: <><circle cx="12" cy="12" r="9" /><circle cx="12" cy="12" r="5" /><circle cx="12" cy="12" r="1.2" fill="currentColor" /></>,
  star: <path d="m12 3.5 2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.9z" />,
  calendar: <><rect x="3.5" y="5" width="17" height="15.5" rx="3" /><path d="M3.5 10h17M8 3v4M16 3v4" /></>,
  seal: <><path d="m12 2.8 2.3 1.7 2.9-.2.9 2.8 2.3 1.7-1 2.7 1 2.7-2.3 1.7-.9 2.8-2.9-.2L12 21.2l-2.3-1.7-2.9.2-.9-2.8-2.3-1.7 1-2.7-1-2.7 2.3-1.7.9-2.8 2.9.2z" /><path d="m8.7 12 2.3 2.3 4.3-4.6" /></>,
  bolt: <path d="M13 2.5 4.5 13.5h6.5l-1 8 8.5-11h-6.5z" />,
  boltCircle: <><circle cx="12" cy="12" r="9" /><path d="M13 6.5 8.5 13h3.8l-1 4.5 4.7-6.5h-3.8z" /></>,
  brain: <><path d="M9.5 4.5A2.8 2.8 0 0 0 6.7 7a3 3 0 0 0-2 4.8 3 3 0 0 0 1.6 4.8 2.9 2.9 0 0 0 3.2 2.9 2 2 0 0 0 2-2V6.5a2 2 0 0 0-2-2z" /><path d="M14.5 4.5A2.8 2.8 0 0 1 17.3 7a3 3 0 0 1 2 4.8 3 3 0 0 1-1.6 4.8 2.9 2.9 0 0 1-3.2 2.9 2 2 0 0 1-2-2V6.5a2 2 0 0 1 2-2z" /></>,
  word: <><path d="M5 4h11a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z" /><path d="M5 17a3 3 0 0 1 3-3h11" /><path d="m9.6 11 2-5 2 5M10.3 9.4h2.6" /></>,
  grid: <><rect x="4" y="4" width="7" height="7" rx="2" /><rect x="13" y="4" width="7" height="7" rx="2" /><rect x="4" y="13" width="7" height="7" rx="2" /><rect x="13" y="13" width="7" height="7" rx="2" /></>,
  zoom: <><circle cx="11" cy="11" r="7" /><path d="m20 20-3.5-3.5M11 8v6M8 11h6" /></>,
  shuffle: <path d="M3 7h3c4.5 0 6.5 10 11 10h4M3 17h3c1.6 0 2.8-1.3 3.9-3M14.1 10c1.1-1.7 2.3-3 3.9-3h3M18.5 4l2.5 3-2.5 3M18.5 14l2.5 3-2.5 3" />,
  book: <><path d="M12 6.5C10 5 7 4.5 4 5v13.5c3-.5 6 0 8 1.5 2-1.5 5-2 8-1.5V5c-3-.5-6 0-8 1.5z" /><path d="M12 6.5V20" /></>,
  xCircle: <><circle cx="12" cy="12" r="9" /><path d="m9 9 6 6M15 9l-6 6" /></>,
  checkCircle: <><circle cx="12" cy="12" r="9" /><path d="m8 12.2 2.8 2.8L16 9.5" /></>,
  flask: <><path d="M9 3h6M10 3v6.2L4.6 18.4A1.8 1.8 0 0 0 6.2 21h11.6a1.8 1.8 0 0 0 1.6-2.6L14 9.2V3" /><path d="M7.2 15h9.6" /></>,
  shield: <><path d="M12 3 4.5 6v5.8c0 4.4 3.2 7.9 7.5 9.2 4.3-1.3 7.5-4.8 7.5-9.2V6z" /><path d="m9 12 2.2 2.2L15.5 10" /></>,
  algorithm: <><rect x="9" y="3" width="6" height="5" rx="1.5" /><rect x="3" y="16" width="6" height="5" rx="1.5" /><rect x="15" y="16" width="6" height="5" rx="1.5" /><path d="M12 8v4M6 16v-2a2 2 0 0 1 2-2h8a2 2 0 0 1 2 2v2" /></>,
  branch: <><circle cx="6" cy="5.5" r="2.2" /><circle cx="6" cy="18.5" r="2.2" /><circle cx="18" cy="7.5" r="2.2" /><path d="M6 7.7v8.6M18 9.7c0 4.3-5 4.3-10.3 7.2" /></>,
  chevron: <path d="m9 6 6 6-6 6" />,
};

export function QIcon({ name, size = 18 }: { name: string; size?: number }) {
  const p = PATHS[name];
  if (!p) return <Icon name={name} size={size} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {p}
    </svg>
  );
}

/** Collection symbols from content.json (flask, shield, brain, algorithm, branch). */
export const collectionIcon = (symbol: string) => (PATHS[symbol] ? symbol : "books");
