// Playbook tints and icons (port of `extension Playbook` in PlaybookView.swift), plus the few extra glyphs the
// shared Icon set lacks. Search imports these for its playbook result rows.
import type { ReactNode } from "react";
import { Icon, tintVar } from "../../ui";

export function themeTint(theme: string): string {
  switch (theme) {
    case "Evals & deception": return tintVar("violet");
    case "Training failures": return tintVar("coral");
    case "Monitoring & control": return tintVar("teal");
    case "Interp & robustness": return tintVar("amber");
    default: return "var(--accent)";
  }
}

export function themeIcon(theme: string): string {
  switch (theme) {
    case "Evals & deception": return "masks";
    case "Training failures": return "refresh";
    case "Monitoring & control": return "eye";
    case "Interp & robustness": return "search";
    default: return "map";
  }
}

export function toolTint(category: string): string {
  switch (category) {
    case "Look inside": case "Steer & edit": return tintVar("teal");
    case "Measure & evaluate": return tintVar("violet");
    case "Data & model organisms": return tintVar("amber");
    case "Oversee & control": return tintVar("coral");
    case "Train for alignment": return tintVar("lime");
    default: return "var(--accent)";
  }
}

export function toolIcon(category: string): string {
  switch (category) {
    case "Look inside": return "search";
    case "Steer & edit": return "settings";
    case "Measure & evaluate": return "ruler";
    case "Data & model organisms": return "tubes";
    case "Oversee & control": return "eye";
    case "Train for alignment": return "grad";
    case "Governance & security": return "columns";
    default: return "wrench";
  }
}

/** Shared Icon plus local extras (same 24px stroke style). */
export function XIcon({ name, size = 18 }: { name: string; size?: number }) {
  const p = EXTRA[name];
  if (!p) return <Icon name={name} size={size} />;
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {p}
    </svg>
  );
}

const EXTRA: Record<string, ReactNode> = {
  masks: <><path d="M3 4c3 1 6 1 9 0v6a4.5 4.5 0 0 1-9 0z" /><path d="M12 10c3 1 6 1 9 0v5a4.5 4.5 0 0 1-9 0" /><path d="M6 8h.01M9 8h.01M15 14h.01M18 14h.01" /></>,
  ruler: <><rect x="2" y="8" width="20" height="8" rx="1.5" /><path d="M6 8v3M10 8v4M14 8v3M18 8v4" /></>,
  tubes: <><path d="M5 3h5M6.5 3v14a1.5 1.5 0 0 0 3 0V3M14 3h5M15.5 3v14a1.5 1.5 0 0 0 3 0V3M6.5 11h3M15.5 13h3" /></>,
  columns: <><path d="M3 21h18M4 10h16M12 3 3 8h18z" /><path d="M6 10v8M10 10v8M14 10v8M18 10v8" /></>,
  question: <><circle cx="12" cy="12" r="9" /><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.7.3-1 .9-1 1.7M12 17h.01" /></>,
  seal: <><path d="M12 2l2.4 2.2 3.2-.4.9 3.1 2.8 1.6-1.2 3 1.2 3-2.8 1.6-.9 3.1-3.2-.4L12 22l-2.4-2.2-3.2.4-.9-3.1-2.8-1.6 1.2-3-1.2-3 2.8-1.6.9-3.1 3.2.4z" /><path d="m8.5 12 2.5 2.5 4.5-5" /></>,
  docsearch: <><path d="M13 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h5" /><path d="M13 3l6 6v2M13 3v6h6" /><circle cx="16" cy="16" r="3" /><path d="m18.2 18.2 2.8 2.8" /></>,
  arrow: <path d="M5 12h14M13 6l6 6-6 6" />,
  clock: <><circle cx="12" cy="12" r="9" /><path d="M12 7v5l3 2" /></>,
  flask: <><path d="M9 3h6M10 3v6L4.5 18.5A1.7 1.7 0 0 0 6 21h12a1.7 1.7 0 0 0 1.5-2.5L14 9V3" /><path d="M7 15h10" /></>,
  shield: <path d="M12 3 4 6v6c0 5 3.5 8 8 9 4.5-1 8-4 8-9V6z" />,
  brain: <><path d="M12 5a3 3 0 0 0-5.5-1.5A3 3 0 0 0 4 8a3 3 0 0 0 0 6 3 3 0 0 0 3 5 3 3 0 0 0 5 1z" /><path d="M12 5a3 3 0 0 1 5.5-1.5A3 3 0 0 1 20 8a3 3 0 0 1 0 6 3 3 0 0 1-3 5 3 3 0 0 1-5 1zM12 5v15" /></>,
  branch: <><circle cx="6" cy="5" r="2" /><circle cx="6" cy="19" r="2" /><circle cx="18" cy="7" r="2" /><path d="M6 7v10M18 9c0 5-6 4-11 8.5" /></>,
};
