// Small pieces shared by the quiz home and session screens (StatTile, ModeTile, MasteryRing).
import type { ReactNode } from "react";
import { Link } from "react-router-dom";
import { tinted } from "../../ui";
import { QIcon } from "./icons";

export function StatTile({ value, label, icon, tint }: { value: string; label: string; icon: string; tint: string }) {
  return (
    <div className="card qz-stat" style={tinted(tint)}>
      <span className="qz-stat-icon"><QIcon name={icon} size={18} /></span>
      <span className="qz-stat-value">{value}</span>
      <span className="qz-stat-label">{label}</span>
    </div>
  );
}

export function ModeTile({ title, subtitle, icon, tint, to, disabled }: { title: string; subtitle: string; icon: string; tint: string; to: string; disabled?: boolean }) {
  const body: ReactNode = (
    <>
      <span className="qz-tile-icon"><QIcon name={icon} size={18} /></span>
      <span className="qz-tile-text">
        <span className="qz-tile-title">{title}</span>
        <span className="qz-tile-sub">{subtitle}</span>
      </span>
    </>
  );
  if (disabled) {
    return <div className="card qz-tile disabled" style={tinted(tint)} aria-disabled="true">{body}</div>;
  }
  return <Link to={to} className="card qz-tile" style={tinted(tint)}>{body}</Link>;
}

/** Share of mastered questions (box 3 or higher) as a ring. */
export function MasteryRing({ value, tint, size = 46 }: { value: number; tint: string; size?: number }) {
  const stroke = 5;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const pct = Math.round(value * 100);
  return (
    <span className="qz-ring" style={tinted(tint, { width: size, height: size })} role="img" aria-label={`${pct}% mastered`}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} aria-hidden="true">
        <circle cx={size / 2} cy={size / 2} r={r} className="qz-ring-track" strokeWidth={stroke} />
        <circle
          cx={size / 2} cy={size / 2} r={r} className="qz-ring-fill" strokeWidth={stroke}
          strokeDasharray={c} strokeDashoffset={c * (1 - Math.max(0.001, value))}
          transform={`rotate(-90 ${size / 2} ${size / 2})`}
        />
      </svg>
      <span className="qz-ring-label" style={{ fontSize: size < 44 ? 10 : 11 }}>{pct}%</span>
    </span>
  );
}
