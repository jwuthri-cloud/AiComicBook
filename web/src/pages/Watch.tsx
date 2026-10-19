// Watch: every narrated clip, one by one or a whole book back to back (port of WatchView.swift + BookPlayerView).
import { useEffect, useRef } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { url, useStore } from "../content";
import { Icon, formatDuration } from "../ui";

export function Watch() {
  const store = useStore();
  const [params, setParams] = useSearchParams();
  const books = store.videoBooks;
  const book = store.books.get(params.get("book") ?? "");
  const clips = book?.pages.filter((p) => p.video) ?? [];
  const clip = Math.min(Number(params.get("clip") ?? 0) || 0, Math.max(clips.length - 1, 0));
  const video = useRef<HTMLVideoElement>(null);
  const total = books.reduce((s, b) => s + b.pages.reduce((t, p) => t + (p.duration ?? 0), 0), 0);

  const play = (bookId: string, i = 0) => setParams({ book: bookId, clip: String(i) });
  useEffect(() => { video.current?.scrollIntoView({ behavior: "smooth", block: "center" }); }, [book?.id]);

  return (
    <div className="stack" style={{ ["--gap" as string]: "28px" }}>
      <header className="stack" style={{ ["--gap" as string]: "6px" }}>
        <h1 className="title-xl">Watch</h1>
        <p className="muted">Short narrated explainers, {formatDuration(total)} in total.</p>
      </header>

      {book && clips[clip] && (
        <section className="card pad stack">
          <video
            ref={video}
            key={clips[clip].id}
            src={url(clips[clip].video!)}
            poster={clips[clip].poster ? url(clips[clip].poster!) : undefined}
            controls
            autoPlay
            playsInline
            onEnded={() => clip < clips.length - 1 && play(book.id, clip + 1)}
            style={{ width: "100%", aspectRatio: "16 / 9", borderRadius: 14, background: "#000" }}
          />
          <div className="row">
            <div className="stack" style={{ ["--gap" as string]: "2px", flex: 1 }}>
              <span className="eyebrow" style={{ color: "var(--accent)" }}>{book.title} · clip {clip + 1} of {clips.length}</span>
              <span className="serif title-m">{clips[clip].title}</span>
            </div>
            <Link to={`/read/${book.id}/${book.pages.indexOf(clips[clip])}?mode=text`} className="btn secondary">Read it</Link>
          </div>
        </section>
      )}

      {books.map((b) => {
        const bClips = b.pages.filter((p) => p.video);
        return (
          <section key={b.id} className="stack">
            <div className="row">
              <div className="stack" style={{ ["--gap" as string]: "2px", flex: 1 }}>
                <h2 className="title-m" style={{ fontWeight: 700 }}>{b.title}</h2>
                <span className="small faint">{bClips.length} clips · {formatDuration(bClips.reduce((s, p) => s + (p.duration ?? 0), 0))}</span>
              </div>
              <button className="btn" onClick={() => play(b.id)}><Icon name="play" />Play all</button>
            </div>
            <div className="hscroll">
              {bClips.map((p, i) => (
                <button key={p.id} onClick={() => play(b.id, i)} className="stack" style={{ ["--gap" as string]: "8px", width: 240, flexShrink: 0, textAlign: "left" }}>
                  <div style={{ position: "relative" }}>
                    <img src={url(p.poster ?? p.thumb)} alt="" loading="lazy" style={{ width: 240, aspectRatio: "16 / 9", objectFit: "cover", borderRadius: 14 }} />
                    <span className="row" style={{ position: "absolute", left: 10, bottom: 8, color: "#fff", fontWeight: 700, ["--gap" as string]: "4px", textShadow: "0 1px 4px rgba(0,0,0,.6)" }}>
                      <Icon name="play" size={14} />{formatDuration(p.duration ?? 0)}
                    </span>
                  </div>
                  <span className="serif" style={{ fontWeight: 600 }}>{i + 1}. {p.title}</span>
                </button>
              ))}
            </div>
          </section>
        );
      })}
    </div>
  );
}
