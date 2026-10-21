// Safety playbook (port of PlaybookView.swift): research questions as decision maps (Experiments), every
// approach in one line (Toolkit), and a recall drill.
import { useState, type ReactNode } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { type Branch, type Playbook, type TreeNode, useStore } from "../../content";
import { useLocal } from "../../store";
import { Icon, Pill, SectionHeader, Segmented, TermChip, tinted, tintVar } from "../../ui";
import { DrillView } from "./Drill";
import { themeIcon, themeTint, toolIcon, toolTint, XIcon } from "./style";
import "./playbook.css";

const PARTS = ["Experiments", "Toolkit", "Drill"] as const;
type Part = (typeof PARTS)[number];

export function PlaybookPage() {
  const store = useStore();
  const [stored, setPart] = useLocal<Part>("playbookPart", "Experiments");
  const part: Part = PARTS.includes(stored) ? stored : "Experiments";
  const [filter, setFilter] = useState("");
  const playbook = store.playbook;

  return (
    <div className="pb-page stack" style={{ ["--gap" as string]: "22px" }}>
      <div className="stack" style={{ ["--gap" as string]: "6px" }}>
        <h1 className="title-xl">Playbook</h1>
        <p className="muted">Research questions as decision maps, every safety tool in one line, and a drill to make them stick.</p>
      </div>
      <Segmented value={part} options={PARTS} onChange={setPart} />
      {!playbook ? (
        <Empty icon="map" title="Playbook not built" text="Run app/tools/build_content.py." />
      ) : part === "Drill" ? (
        <DrillView playbook={playbook} />
      ) : (
        <>
          <div className="pb-filter">
            <Icon name="search" size={17} />
            <input
              className="input"
              type="search"
              value={filter}
              onChange={(e) => setFilter(e.target.value)}
              placeholder={part === "Toolkit" ? "Find a tool" : "Find a question"}
              aria-label={part === "Toolkit" ? "Find a tool" : "Find a question"}
            />
          </div>
          {part === "Experiments" ? <Experiments playbook={playbook} filter={filter} /> : <Toolkit playbook={playbook} filter={filter} />}
        </>
      )}
    </div>
  );
}

const unique = (xs: string[]) => [...new Set(xs)];

function matcher(filter: string) {
  const q = filter.trim().toLowerCase();
  return (...texts: string[]) => !q || texts.some((t) => t.toLowerCase().includes(q));
}

function Experiments({ playbook, filter }: { playbook: Playbook; filter: string }) {
  const matches = matcher(filter);
  const groups = unique(playbook.experiments.map((e) => e.theme))
    .map((theme) => ({ theme, items: playbook.experiments.filter((e) => e.theme === theme && matches(e.question, e.chain, e.theme)) }))
    .filter((g) => g.items.length);
  return (
    <>
      {!filter.trim() && <RecipeStrip recipe={playbook.recipe} />}
      {groups.map(({ theme, items }) => (
        <section key={theme} className="stack" style={{ ["--gap" as string]: "10px" }}>
          <SectionHeader title={theme} icon={<XIcon name={themeIcon(theme)} size={17} />} tint={themeTint(theme)} />
          <div className="pb-exp-grid">
            {items.map((e) => (
              <Link key={e.id} to={`/playbook/experiment/${e.id}`} className="card pb-exp" style={tinted(themeTint(theme))}>
                <span className="pb-exp-q">{e.question}</span>
                <span className="pb-exp-chain">{e.chain}</span>
              </Link>
            ))}
          </div>
        </section>
      ))}
      {!groups.length && <p className="muted">No question matches “{filter.trim()}”.</p>}
    </>
  );
}

function Toolkit({ playbook, filter }: { playbook: Playbook; filter: string }) {
  const matches = matcher(filter);
  const groups = unique(playbook.tools.map((t) => t.category))
    .map((category) => ({ category, items: playbook.tools.filter((t) => t.category === category && matches(t.name, t.what, t.useWhen)) }))
    .filter((g) => g.items.length);
  return (
    <>
      {groups.map(({ category, items }) => (
        <section key={category} className="stack" style={{ ["--gap" as string]: "8px" }}>
          <SectionHeader title={category} icon={<XIcon name={toolIcon(category)} size={17} />} tint={toolTint(category)} />
          <div className="card pb-list">
            {items.map((tool) => (
              <Link key={tool.id} to={`/playbook/tool/${tool.id}`} className="pb-list-row">
                <span className="stack" style={{ ["--gap" as string]: "3px", flex: 1, minWidth: 0 }}>
                  <span className="pb-tool-name">{tool.name}</span>
                  <span className="pb-tool-what">{tool.what}</span>
                </span>
                <span className="pb-chevron"><Icon name="right" size={15} /></span>
              </Link>
            ))}
          </div>
        </section>
      ))}
      {!groups.length && <p className="muted">No tool matches “{filter.trim()}”.</p>}
    </>
  );
}

/** The generic recipe, numbered, above the experiment list. */
function RecipeStrip({ recipe }: { recipe: string[] }) {
  return (
    <div className="pb-recipe">
      <span className="eyebrow" style={{ color: "var(--accent)" }}>The recipe behind every map</span>
      <ol className="pb-recipe-steps">
        {recipe.map((step, i) => (
          <li key={i}>
            <span className="pb-recipe-n">{i + 1}</span>
            <span>{step}</span>
            {i < recipe.length - 1 && <span className="faint" aria-hidden="true"><XIcon name="arrow" size={13} /></span>}
          </li>
        ))}
      </ol>
    </div>
  );
}

// ---------- Experiment map ----------

export function ExperimentPage() {
  const { experimentId } = useParams();
  const store = useStore();
  const experiment = store.playbook?.experiments.find((e) => e.id === experimentId);
  if (!experiment) return <NotFound what="experiment" />;
  const tint = themeTint(experiment.theme);
  const book = experiment.fellowship ? store.books.get(experiment.fellowship) : undefined;
  const route = experiment.chain.split(/\s*(?:→|->)\s*/).filter(Boolean);
  const forks = experiment.tree.filter((n) => n.branches?.length).length;

  return (
    <article className="narrow stack" style={{ ["--gap" as string]: "24px", ...tinted(tint) }}>
      <BackButton />
      <header className="stack" style={{ ["--gap" as string]: "12px", alignItems: "flex-start" }}>
        <Pill text={experiment.theme} tint={tint} icon={<XIcon name={themeIcon(experiment.theme)} size={14} />} />
        <h1 className="title-l">{experiment.question}</h1>
        <p className="muted small">{experiment.tree.length} steps{forks ? ` · ${forks} decision ${forks === 1 ? "point" : "points"}` : ""}</p>
        <ol className="pb-route" aria-label="At a glance">
          {route.map((r, i) => (
            <li key={i}><span className="pb-route-n">{i + 1}</span>{r}</li>
          ))}
        </ol>
      </header>

      <ol className="pb-steps">
        {experiment.tree.map((node, i) => <StepCard key={i} node={node} n={i + 1} last={i === experiment.tree.length - 1} />)}
      </ol>

      <div className="stack" style={{ ["--gap" as string]: "12px" }}>
        <InfoRow title="Watch out" text={experiment.confound} icon="warn" tint={tintVar("coral")} />
        <InfoRow title="Success looks like" text={experiment.success} icon="seal" tint={tintVar("lime")} />
        {experiment.example && <InfoRow title="Real example" text={experiment.example} icon="docsearch" tint={tintVar("violet")} />}
      </div>

      {book && (
        <Link to={`/b/${book.id}`} className="btn secondary block pb-fellowship" style={tinted(tint)}>
          <Icon name="books" />
          <span>Read the fellowship book: {book.title}</span>
        </Link>
      )}
    </article>
  );
}

/** One top-level step: numbered marker on a connector rail, the step as a card, decisions as a fork below it. */
function StepCard({ node, n, last }: { node: TreeNode; n: number; last: boolean }) {
  return (
    <li className={`pb-stepwrap${last ? " last" : ""}`}>
      <div className="pb-rail" aria-hidden="true">
        <span className="pb-num">{n}</span>
        {!last && <span className="pb-line" />}
      </div>
      <div className="pb-stepcol">
        <div className="card pb-card">
          <StepBody node={node} title="pb-step" />
        </div>
        {node.branches?.length ? (
          <div className="pb-fork">
            <span className="pb-fork-label"><Icon name="turn" size={14} />Decision: what did you find?</span>
            <div className="pb-fork-grid">
              {node.branches.map((b, i) => <BranchCard key={i} branch={b} color={BRANCH_TINTS[i % BRANCH_TINTS.length]} />)}
            </div>
          </div>
        ) : null}
      </div>
    </li>
  );
}

const BRANCH_TINTS = ["teal", "amber", "violet"].map(tintVar);

function BranchCard({ branch, color }: { branch: Branch; color: string }) {
  return (
    <div className="pb-branch" style={{ ["--b" as string]: color }}>
      <span className="pb-branch-if">If {branch.if.replace(/^if\s+/i, "")}</span>
      {branch.then.map((node, i) => (
        <div key={i} className="pb-substep">
          <StepBody node={node} title="pb-substep-title" />
          {node.branches?.map((b, j) => <BranchCard key={j} branch={b} color={color} />)}
        </div>
      ))}
    </div>
  );
}

/** Title, how-to, tool link and outcome; shared by steps and branch steps. */
function StepBody({ node, title }: { node: TreeNode; title: string }) {
  const store = useStore();
  const tool = node.tool ? store.tools.get(node.tool) : undefined;
  return (
    <>
      <span className={title}>{node.step}</span>
      {node.how && <span className="pb-how">{node.how}</span>}
      {(tool || node.outcome) && (
        <div className="pb-meta">
          {tool && (
            <Link to={`/playbook/tool/${tool.id}`} className="pb-tool" style={tinted(toolTint(tool.category))}>
              <Icon name="wrench" size={13} />
              {tool.name}
            </Link>
          )}
          {node.outcome && (
            <span className="pb-outcome"><Icon name="flag" size={14} />{node.outcome}</span>
          )}
        </div>
      )}
    </>
  );
}

function InfoRow({ title, text, icon, tint }: { title: string; text: string; icon: string; tint: string }) {
  return (
    <div className="card pb-info" style={tinted(tint)}>
      <span className="pb-info-icon"><XIcon name={icon} size={19} /></span>
      <div className="stack" style={{ ["--gap" as string]: "3px", minWidth: 0 }}>
        <span className="pb-info-title">{title}</span>
        <p className="pb-info-text">{text}</p>
      </div>
    </div>
  );
}

// ---------- Tool detail ----------

export function ToolPage() {
  const { toolId } = useParams();
  const store = useStore();
  const tool = toolId ? store.tools.get(toolId) : undefined;
  if (!tool) return <NotFound what="tool" />;
  const tint = toolTint(tool.category);
  const terms = tool.terms.map((id) => store.terms.get(id)).filter((t) => t !== undefined);
  const used = store.experimentsUsing(tool.id);

  return (
    <article className="narrow stack" style={{ ["--gap" as string]: "20px" }}>
      <BackButton />
      <header className="stack" style={{ ["--gap" as string]: "10px", alignItems: "flex-start" }}>
        <Pill text={tool.category} tint={tint} icon={<XIcon name={toolIcon(tool.category)} size={14} />} />
        <h1 className="title-xl">{tool.name}</h1>
      </header>
      <div className="stack" style={{ ["--gap" as string]: "12px" }}>
        <InfoRow title="What it is" text={tool.what} icon="bulb" tint={tint} />
        <InfoRow title="Use it when" text={tool.useWhen} icon="question" tint={tintVar("teal")} />
        <InfoRow title="Catch" text={tool.catch} icon="warn" tint={tintVar("coral")} />
      </div>

      {terms.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "10px" }}>
          <h2 className="pb-h2">In the glossary</h2>
          <div className="wrap">{terms.map((t) => <TermChip key={t.id} term={t} />)}</div>
        </section>
      )}

      {used.length > 0 && (
        <section className="stack" style={{ ["--gap" as string]: "10px" }}>
          <h2 className="pb-h2">Used in {used.length} {used.length === 1 ? "experiment" : "experiments"}</h2>
          {used.map((e) => (
            <Link key={e.id} to={`/playbook/experiment/${e.id}`} className="card pb-used">
              <span className="pb-used-q">{e.question}</span>
              <span className="pb-chevron"><Icon name="right" size={15} /></span>
            </Link>
          ))}
        </section>
      )}
    </article>
  );
}

// ---------- bits ----------

/** History back when there is somewhere to go back to, else the playbook. */
function BackButton() {
  const navigate = useNavigate();
  const canGoBack = ((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0;
  return (
    <button className="pb-back" onClick={() => (canGoBack ? navigate(-1) : navigate("/playbook"))}>
      <Icon name="left" size={16} />
      {canGoBack ? "Back" : "Playbook"}
    </button>
  );
}

function NotFound({ what }: { what: string }) {
  return (
    <div className="narrow stack">
      <Empty icon="map" title={`No such ${what}`} text="It may have been renamed in a content update.">
        <Link to="/playbook" className="btn secondary">Open the playbook</Link>
      </Empty>
    </div>
  );
}

function Empty({ icon, title, text, children }: { icon: string; title: string; text: string; children?: ReactNode }) {
  return (
    <div className="pb-empty">
      <span className="faint"><Icon name={icon} size={36} /></span>
      <h2 className="title-m">{title}</h2>
      <p className="muted small">{text}</p>
      {children}
    </div>
  );
}
