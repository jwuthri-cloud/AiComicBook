// Port of QuizHomeView.swift: stats, daily quiz, quick modes, practice games and per-collection quizzes.
import { useMemo } from "react";
import { Link, useSearchParams } from "react-router-dom";
import { type Collection, useStore } from "../../content";
import { BookCover, Icon, SectionHeader, tinted, tintVar } from "../../ui";
import { usePracticeBests } from "../practice";
import { allItemIds, mastery, needsReview, questionsForBook, questionsForCollection, quizPath } from "./engine";
import { collectionIcon, QIcon } from "./icons";
import { MasteryRing, ModeTile, StatTile } from "./parts";
import { useQuizState } from "./state";
import "./quiz.css";

export function QuizHome() {
  const [params] = useSearchParams();
  const store = useStore();
  const collection = store.collectionsById.get(params.get("collection") ?? "");
  return collection ? <CollectionQuiz key={collection.id} collection={collection} /> : <Home />;
}

const best = (v: unknown) => (typeof v === "number" && Number.isFinite(v) && v > 0 ? v : 0);

function Home() {
  const store = useStore();
  const quiz = useQuizState();
  const bests = usePracticeBests();
  const { snapshot } = quiz;

  const reviewCount = useMemo(() => allItemIds(store).filter((id) => needsReview(snapshot, id)).length, [store, snapshot]);

  const collectionIds = useMemo(
    () => new Map(store.collections.map((c) => [c.id, questionsForCollection(store, c.id).map((q) => q.id)])),
    [store],
  );

  const done = quiz.dailyDoneToday;
  const violet = tintVar("violet");
  const match = best(bests.match);
  const speed = best(bests.speed);
  const zoom = best(bests.zoom);

  return (
    <div className="narrow stack qz-home" style={{ ["--gap" as string]: "28px" }}>
      <header className="stack" style={{ ["--gap" as string]: "6px" }}>
        <h1 className="title-xl">Quiz</h1>
        <p className="muted">
          {store.quiz.length} questions on every page, plus {store.glossary.length * 2} word questions. Missed ones come back until they stick.
        </p>
      </header>

      <div className="qz-stats">
        <StatTile value={String(quiz.streak)} label="day streak" icon="flame" tint={tintVar("coral")} />
        <StatTile value={quiz.accuracy === null ? "–" : `${Math.round(quiz.accuracy * 100)}%`} label="accuracy" icon="target" tint={tintVar("teal")} />
        <StatTile value={String(quiz.xp)} label="points" icon="star" tint={tintVar("amber")} />
      </div>

      <Link to={quizPath(done ? { mode: "quick" } : { mode: "daily" })} className="qz-daily" style={tinted(violet)}>
        <span className="stack" style={{ ["--gap" as string]: "8px", flex: 1, minWidth: 0 }}>
          <span className="qz-daily-eyebrow">
            <QIcon name={done ? "seal" : "calendar"} size={15} />
            {done ? "Done for today" : "Today's quiz"}
          </span>
          <span className="qz-daily-title">{done ? "Bonus round" : "Daily 10"}</span>
          <span className="qz-daily-sub">
            {done ? "Five more questions while you have a minute." : "Eight page questions and two words, picked to fill the gaps."}
          </span>
        </span>
        <span className="qz-daily-play"><Icon name="play" size={22} /></span>
      </Link>

      <div className="qz-tiles">
        <ModeTile
          title="Review" subtitle={reviewCount === 0 ? "Nothing due" : `${reviewCount} due`}
          icon="refresh" tint={tintVar("coral")} to={quizPath({ mode: "review" })} disabled={reviewCount === 0}
        />
        <ModeTile title="Word drill" subtitle="Glossary terms" icon="word" tint={tintVar("teal")} to={quizPath({ mode: "words" })} />
        <ModeTile title="Quick 5" subtitle="Anything goes" icon="bolt" tint={tintVar("amber")} to={quizPath({ mode: "quick" })} />
        <ModeTile title="Hard mode" subtitle="Reasoning questions" icon="brain" tint={tintVar("lime")} to={quizPath({ mode: "hard" })} />
      </div>

      <section className="stack" style={{ ["--gap" as string]: "14px" }}>
        <SectionHeader title="Play" />
        <div className="qz-tiles">
          <ModeTile title="Flashcards" subtitle="Flip and swipe" icon="cards" tint={tintVar("teal")} to="/flashcards" />
          <ModeTile title="Match" subtitle={match ? `Best ${match.toFixed(1)} s` : "Words ↔ meanings"} icon="grid" tint={violet} to="/games/match" />
          <ModeTile title="Speed round" subtitle={speed ? `Best ${speed} pts` : "60 seconds, right or wrong"} icon="boltCircle" tint={tintVar("amber")} to="/games/speed" />
          <ModeTile title="Zoom guess" subtitle={zoom ? `Best ${zoom} of 24` : "Which page is this?"} icon="zoom" tint={tintVar("coral")} to="/games/zoom" />
        </div>
      </section>

      <section className="stack" style={{ ["--gap" as string]: "14px" }}>
        <SectionHeader title="By collection" />
        <div className="stack" style={{ ["--gap" as string]: "12px" }}>
          {store.collections.map((c) => {
            const ids = collectionIds.get(c.id) ?? [];
            const tint = tintVar(c.tint);
            return (
              <Link key={c.id} to={`/quiz?collection=${encodeURIComponent(c.id)}`} className="card qz-row" style={tinted(tint)}>
                <span className="qz-row-icon"><QIcon name={collectionIcon(c.symbol)} size={19} /></span>
                <span className="qz-row-text">
                  <span className="qz-row-title">{c.title}</span>
                  <span className="qz-row-sub">{ids.length} questions · {c.books.length} books</span>
                </span>
                <MasteryRing value={mastery(snapshot, ids)} tint={tint} />
              </Link>
            );
          })}
        </div>
      </section>
    </div>
  );
}

/** Port of CollectionQuizView: a mixed quiz plus one quiz per book. */
function CollectionQuiz({ collection }: { collection: Collection }) {
  const store = useStore();
  const { snapshot } = useQuizState();
  const tint = tintVar(collection.tint);
  const books = useMemo(
    () => collection.books.map((b) => ({ book: b, ids: questionsForBook(store, b.id).map((q) => q.id) })),
    [store, collection],
  );

  return (
    <div className="narrow stack qz-home" style={tinted(tint, { ["--gap" as string]: "20px" })}>
      <Link to="/quiz" className="qz-back"><Icon name="left" size={16} />Quiz</Link>
      <header className="stack" style={{ ["--gap" as string]: "6px" }}>
        <span className="eyebrow">Collection quiz</span>
        <h1 className="title-l">{collection.title}</h1>
        {collection.subtitle && <p className="muted">{collection.subtitle}</p>}
      </header>

      <Link to={quizPath({ mode: "collection", id: collection.id })} className="card qz-mixed">
        <span className="qz-row-icon"><QIcon name="shuffle" size={19} /></span>
        <span className="qz-row-text">
          <span className="qz-row-title">Mixed quiz from all {collection.books.length} books</span>
          <span className="qz-row-sub">12 questions, weighted towards what you missed</span>
        </span>
        <QIcon name="chevron" size={18} />
      </Link>

      <section className="stack" style={{ ["--gap" as string]: "12px" }}>
        <span className="eyebrow">Books</span>
        {books.map(({ book, ids }) => {
          const body = (
            <>
              <BookCover book={book} width={44} />
              <span className="qz-row-text">
                <span className="qz-row-title qz-clamp">{book.title}</span>
                <span className="qz-row-sub">{ids.length ? `${ids.length} questions` : "No questions yet"}</span>
              </span>
              <MasteryRing value={mastery(snapshot, ids)} tint={tint} size={42} />
            </>
          );
          return ids.length ? (
            <Link key={book.id} to={quizPath({ mode: "book", id: book.id })} className="card qz-row">{body}</Link>
          ) : (
            <div key={book.id} className="card qz-row disabled" aria-disabled="true">{body}</div>
          );
        })}
      </section>
    </div>
  );
}
