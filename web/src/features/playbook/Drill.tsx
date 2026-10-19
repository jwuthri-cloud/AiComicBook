// Recall drill (port of DrillView.swift): see a research question, recall the steps, reveal them one by one.
// Plus a tool-matching quiz.
import { useState } from "react";
import { Link } from "react-router-dom";
import { type Experiment, type Playbook, type Store, type Tool, type TreeNode, useStore } from "../../content";
import { useLocal } from "../../store";
import { Icon, Pill, Segmented, tinted, tintVar } from "../../ui";
import { themeIcon, themeTint, toolTint, XIcon } from "./style";

const MODES = ["Recall the map", "Match the tool"] as const;
type Mode = (typeof MODES)[number];

export function DrillView({ playbook }: { playbook: Playbook }) {
  const [mode, setMode] = useState<Mode>("Recall the map");
  return (
    <div className="stack" style={{ ["--gap" as string]: "18px" }}>
      <Segmented value={mode} options={MODES} onChange={setMode} />
      {mode === "Recall the map" ? <RecallDrill experiments={playbook.experiments} /> : <ToolMatchDrill playbook={playbook} />}
    </div>
  );
}

const pickRandom = <T,>(xs: T[]): T | undefined => xs[Math.floor(Math.random() * xs.length)];

function shuffled<T>(xs: T[]): T[] {
  const a = [...xs];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

// ---------- Recall ----------

/** Unmastered questions first; once all are mastered, anything goes. */
function nextExperiment(experiments: Experiment[], mastered: string[], current?: Experiment) {
  const pool = experiments.filter((e) => !mastered.includes(e.id) && e.id !== current?.id);
  const fallback = experiments.filter((e) => e.id !== current?.id);
  return pickRandom(pool.length ? pool : fallback) ?? experiments[0];
}

function RecallDrill({ experiments }: { experiments: Experiment[] }) {
  const store = useStore();
  const [mastered, setMastered] = useLocal<string[]>("playbookMastered", []);
  const [current, setCurrent] = useState<Experiment | undefined>(() => nextExperiment(experiments, mastered));
  const [revealed, setRevealed] = useState(0);

  const next = (masteredNow = mastered) => {
    setCurrent(nextExperiment(experiments, masteredNow, current));
    setRevealed(0);
  };
  const mark = (e: Experiment, got: boolean) => {
    const set = new Set(mastered);
    if (got) set.add(e.id); else set.delete(e.id);
    const updated = [...set].sort();
    setMastered(updated);
    next(updated);
  };
  const count = experiments.filter((e) => mastered.includes(e.id)).length;

  return (
    <div className="stack">
      <div className="row">
        <span className="small muted" style={{ fontWeight: 600 }}>{count} of {experiments.length} mastered</span>
        <span className="spacer" />
        <button className="pb-link-btn" onClick={() => next()}>Skip</button>
      </div>
      {current && (() => {
        const e = current;
        const tint = themeTint(e.theme);
        const steps = e.tree;
        return (
          <div key={e.id} className="card pb-drill-card pb-in" style={tinted(tint)}>
            <Pill text={e.theme} tint={tint} icon={<XIcon name={themeIcon(e.theme)} size={14} />} />
            <h2 className="title-l">{e.question}</h2>
            {revealed === 0 && (
              <p className="pb-hint">Say the steps in your head first: what would you check, build and compare?</p>
            )}
            {steps.length > 0 && revealed > 0 && (
              <ol className="pb-recall-steps">
                {steps.slice(0, revealed).map((node, i) => {
                  const tool = node.tool ? store.tools.get(node.tool) : undefined;
                  return (
                    <li key={i} className="pb-in">
                      <span className="pb-num" style={{ width: 24, height: 24 }}>{i + 1}</span>
                      <span className="stack" style={{ ["--gap" as string]: "2px" }}>
                        <span className="pb-step">{node.step}</span>
                        {tool && <span className="pb-recall-tool" style={tinted(toolTint(tool.category))}>{tool.name}</span>}
                      </span>
                    </li>
                  );
                })}
              </ol>
            )}
            {revealed < steps.length ? (
              <button className="btn block" onClick={() => setRevealed((r) => r + 1)}>
                <Icon name="eye" />
                Reveal step {revealed + 1}
              </button>
            ) : (
              <>
                <p className="pb-chain-text">{e.chain}</p>
                <Link to={`/playbook/experiment/${e.id}`} className="btn secondary block">
                  <Icon name="map" />
                  Open the full map
                </Link>
                <div className="row" style={{ ["--gap" as string]: "12px" }}>
                  <button className="btn secondary" style={tinted(tintVar("coral"), { flex: 1 })} onClick={() => mark(e, false)}>
                    <Icon name="refresh" />
                    Missed
                  </button>
                  <button className="btn" style={tinted(tintVar("lime"), { flex: 1 })} onClick={() => mark(e, true)}>
                    <Icon name="check" />
                    Got it
                  </button>
                </div>
              </>
            )}
          </div>
        );
      })()}
    </div>
  );
}

// ---------- Tool match ----------

interface Item { experiment: Experiment; node: TreeNode; tool: Tool; options: Tool[] }

function makeItem(playbook: Playbook, store: Store): Item | undefined {
  // Every node that names a tool and says how it is used, at any depth.
  const pairs: [Experiment, TreeNode][] = [];
  const walk = (nodes: TreeNode[], e: Experiment) => {
    for (const n of nodes) {
      if (n.tool && n.how) pairs.push([e, n]);
      for (const b of n.branches ?? []) walk(b.then, e);
    }
  };
  for (const e of playbook.experiments) walk(e.tree, e);
  const pair = pickRandom(pairs);
  const tool = pair?.[1].tool ? store.tools.get(pair[1].tool) : undefined;
  if (!pair || !tool) return undefined;
  // Distractors: other tools used somewhere in the maps, so every option is plausible.
  const used = [...new Set(pairs.map(([, n]) => n.tool!))]
    .filter((id) => id !== tool.id)
    .map((id) => store.tools.get(id))
    .filter((t) => t !== undefined);
  return { experiment: pair[0], node: pair[1], tool, options: shuffled([...shuffled(used).slice(0, 3), tool]) };
}

function ToolMatchDrill({ playbook }: { playbook: Playbook }) {
  const store = useStore();
  const [item, setItem] = useState(() => makeItem(playbook, store));
  const [picked, setPicked] = useState<string>();
  const [score, setScore] = useState(0);
  const [asked, setAsked] = useState(0);

  const pick = (option: Tool) => {
    if (!item || picked) return;
    setPicked(option.id);
    setAsked((n) => n + 1);
    if (option.id === item.tool.id) setScore((n) => n + 1);
  };
  const next = () => {
    setItem(makeItem(playbook, store));
    setPicked(undefined);
  };
  const color = (option: Tool) => {
    if (!picked || !item) return "var(--ink)";
    if (option.id === item.tool.id) return tintVar("lime");
    return picked === option.id ? tintVar("coral") : "var(--ink-3)";
  };

  return (
    <div className="stack">
      <span className="small muted" style={{ fontWeight: 600 }}>
        {asked === 0 ? "Which tool does this step need?" : `${score} / ${asked} right`}
      </span>
      {item && (
        <div key={`${item.experiment.id}:${item.node.step}`} className="card pb-drill-card pb-in" style={tinted(themeTint(item.experiment.theme))}>
          <span className="pb-match-q">{item.experiment.question}</span>
          <h2 className="pb-match-step">{item.node.step}</h2>
          {item.node.how && <p className="pb-match-how">{item.node.how}</p>}
          <div className="stack" style={{ ["--gap" as string]: "8px" }}>
            {item.options.map((option) => {
              const right = picked && option.id === item.tool.id;
              const wrong = picked === option.id && !right;
              return (
                <button
                  key={option.id}
                  className={`pb-option${picked ? " done" : ""}`}
                  style={{ ["--c" as string]: color(option) }}
                  disabled={!!picked}
                  onClick={() => pick(option)}
                >
                  <span>{option.name}</span>
                  {right && <Icon name="check" />}
                  {wrong && <Icon name="close" />}
                </button>
              );
            })}
          </div>
          {picked && (
            <>
              <p className="pb-match-explain"><strong>{item.tool.name}:</strong> {item.tool.what}</p>
              <button className="btn block" onClick={next}>
                Next
                <XIcon name="arrow" />
              </button>
            </>
          )}
        </div>
      )}
    </div>
  );
}
