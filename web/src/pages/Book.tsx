import { Link, useParams } from "react-router-dom";
import { url, useStore } from "../content";
import { useLibrary } from "../store";
import { BookCover, Icon, formatDuration, tintVar, tinted } from "../ui";

export function CollectionPage() {
  const store = useStore();
  const { collectionId } = useParams();
  const collection = store.collectionsById.get(collectionId ?? "");
  const library = useLibrary();
  if (!collection) return <p className="muted">Collection not found.</p>;
  const tint = tintVar(collection.tint);
  return (
    <div className="stack" style={{ ["--gap" as string]: "24px" }}>
      <header className="stack" style={{ ["--gap" as string]: "8px" }}>
        <span className="eyebrow" style={{ color: tint }}>{collection.subtitle}</span>
        <h1 className="title-xl">{collection.title}</h1>
        <p className="serif muted" style={{ fontSize: 18, maxWidth: 640 }}>{collection.description}</p>
        <span className="small faint">{collection.books.length} books · {collection.pageCount} pages</span>
      </header>
      <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(140px, 1fr))" }}>
        {collection.books.map((book) => {
          const progress = library.progress(book);
          return (
            <Link key={book.id} to={`/b/${book.id}`} className="stack" style={{ ["--gap" as string]: "6px" }}>
              <BookCover book={book} width={140} />
              <span className="serif small" style={{ fontWeight: 600 }}>{book.title}</span>
              <span className="tiny faint">{book.subtitle}</span>
              {progress > 0 && <span className="progress" style={tinted(tint)}><div style={{ width: `${progress * 100}%` }} /></span>}
            </Link>
          );
        })}
      </div>
    </div>
  );
}

export function BookPage() {
  const store = useStore();
  const { bookId } = useParams();
  const library = useLibrary();
  const book = store.books.get(bookId ?? "");
  if (!book) return <p className="muted">Book not found.</p>;
  const collection = store.collectionFor(book);
  const tint = tintVar(collection?.tint ?? "teal");
  const last = library.lastPageIndex(book);
  const started = library.lib.recentBooks.includes(book.id);
  return (
    <div className="stack" style={{ ["--gap" as string]: "26px", ...tinted(tint) }}>
      <header className="row" style={{ ["--gap" as string]: "20px", alignItems: "flex-end", flexWrap: "wrap" }}>
        <BookCover book={book} width={150} />
        <div className="stack" style={{ ["--gap" as string]: "8px", flex: 1, minWidth: 240 }}>
          <Link to={`/c/${collection?.id}`} className="eyebrow" style={{ color: tint }}>{collection?.title}</Link>
          <h1 className="title-xl">{book.title}</h1>
          <span className="muted">{book.subtitle} · {book.pages.length} pages{book.hasVideo ? ` · ${formatDuration(book.pages.reduce((s, p) => s + (p.duration ?? 0), 0))} of video` : ""}</span>
          <div className="wrap" style={{ marginTop: 6 }}>
            <Link to={`/read/${book.id}/${started ? last : 0}`} className="btn"><Icon name="books" />{started ? `Continue · page ${last + 1}` : "Start reading"}</Link>
            {book.hasVideo && <Link to={`/watch?book=${book.id}`} className="btn secondary"><Icon name="play" />Watch</Link>}
            <Link to={`/quiz/play?mode=book&id=${book.id}`} className="btn secondary"><Icon name="quiz" />Quiz</Link>
          </div>
        </div>
      </header>

      {book.objectives.length > 0 && (
        <section className="card pad stack" style={{ ["--gap" as string]: "10px" }}>
          <span className="eyebrow">What you'll learn</span>
          {book.objectives.map((o) => (
            <div key={o} className="row" style={{ alignItems: "flex-start" }}>
              <span style={{ color: tint, marginTop: 2 }}><Icon name="check" /></span>
              <span className="serif">{o}</span>
            </div>
          ))}
        </section>
      )}

      <section className="stack">
        <h2 className="title-m" style={{ fontWeight: 700 }}>Pages</h2>
        <div className="grid" style={{ gridTemplateColumns: "repeat(auto-fill, minmax(150px, 1fr))" }}>
          {book.pages.map((page, i) => (
            <Link key={page.id} to={`/read/${book.id}/${i}`} className="stack" style={{ ["--gap" as string]: "6px" }}>
              <div style={{ position: "relative" }}>
                <img src={url(page.thumb)} alt="" loading="lazy" style={{ width: "100%", aspectRatio: "2 / 3", objectFit: "cover", borderRadius: 10, boxShadow: "0 4px 12px rgba(0,0,0,.15)", opacity: library.isRead(page) ? 0.75 : 1 }} />
                {library.isRead(page) && <span className="pill" style={{ position: "absolute", top: 6, right: 6, background: "var(--surface)" }}><Icon name="check" size={13} />Read</span>}
              </div>
              <span className="tiny faint">Page {page.number}</span>
              <span className="serif small" style={{ fontWeight: 600 }}>{page.title}</span>
            </Link>
          ))}
        </div>
      </section>
    </div>
  );
}
