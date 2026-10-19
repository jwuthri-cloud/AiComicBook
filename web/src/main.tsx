import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { BrowserRouter, NavLink, Route, Routes, useLocation } from "react-router-dom";
import "./theme.css";
import { loadStore, type Store, StoreContext } from "./content";
import { useAppearance } from "./store";
import { Icon } from "./ui";
import { Home, Bookmarks, Settings } from "./pages/Home";
import { CollectionPage, BookPage } from "./pages/Book";
import { Reader } from "./pages/Reader";
import { Watch } from "./pages/Watch";
import { GlossaryPage, TermPage, ConceptMapPage } from "./features/glossary";
import { FlashcardsPage, GamePage } from "./features/practice";
import { QuizHome, QuizPlay } from "./features/quiz";
import { PlaybookPage, ToolPage, ExperimentPage } from "./features/playbook";
import { SearchPage } from "./features/search";
import { ListenBar, ListenProvider } from "./features/listen";
import { AssistantProvider } from "./features/assistant";

const TABS = [
  { to: "/", label: "Library", icon: "books", end: true },
  { to: "/playbook", label: "Playbook", icon: "map" },
  { to: "/quiz", label: "Quiz", icon: "quiz" },
  { to: "/glossary", label: "Glossary", icon: "glossary" },
  { to: "/search", label: "Search", icon: "search" },
];

function Nav({ bottom }: { bottom?: boolean }) {
  return (
    <>
      {TABS.map((t) => (
        <NavLink key={t.to} to={t.to} end={t.end} className={({ isActive }) => `navlink${isActive ? " active" : ""}`}>
          <Icon name={t.icon} size={bottom ? 22 : 17} />
          {t.label}
        </NavLink>
      ))}
    </>
  );
}

function Shell() {
  const location = useLocation();
  const reading = location.pathname.startsWith("/read/");
  useEffect(() => { window.scrollTo(0, 0); }, [location.pathname]); // braces: newer browsers return a Promise from scrollTo
  return (
    <div className="shell">
      {!reading && (
        <header className="topnav">
          <div className="topnav-inner">
            <NavLink to="/" className="brand"><img src="/icon.png" alt="" />Safety Atlas</NavLink>
            <Nav />
            <span className="spacer" />
            <NavLink to="/settings" className="iconbtn" aria-label="Settings"><Icon name="settings" /></NavLink>
          </div>
        </header>
      )}
      <Routes>
        <Route path="/read/:bookId/:index?" element={<Reader />} />
        <Route path="*" element={<main className="main"><Pages /></main>} />
      </Routes>
      <ListenBar />
      {!reading && <nav className="tabbar"><Nav bottom /></nav>}
    </div>
  );
}

function Pages() {
  return (
    <Routes>
      <Route path="/" element={<Home />} />
      <Route path="/c/:collectionId" element={<CollectionPage />} />
      <Route path="/b/:bookId" element={<BookPage />} />
      <Route path="/watch" element={<Watch />} />
      <Route path="/bookmarks" element={<Bookmarks />} />
      <Route path="/settings" element={<Settings />} />
      <Route path="/glossary" element={<GlossaryPage />} />
      <Route path="/glossary/:termId" element={<TermPage />} />
      <Route path="/map/:termId" element={<ConceptMapPage />} />
      <Route path="/flashcards" element={<FlashcardsPage />} />
      <Route path="/games/:game" element={<GamePage />} />
      <Route path="/quiz" element={<QuizHome />} />
      <Route path="/quiz/play" element={<QuizPlay />} />
      <Route path="/playbook" element={<PlaybookPage />} />
      <Route path="/playbook/tool/:toolId" element={<ToolPage />} />
      <Route path="/playbook/experiment/:experimentId" element={<ExperimentPage />} />
      <Route path="/search" element={<SearchPage />} />
      <Route path="*" element={<div className="narrow"><h1 className="title-l">Not found</h1></div>} />
    </Routes>
  );
}

function App() {
  const [store, setStore] = useState<Store | null>(null);
  const [error, setError] = useState<string>();
  const [appearance] = useAppearance();
  useEffect(() => { loadStore().then(setStore, (e) => setError(String(e))); }, []);
  useEffect(() => {
    if (appearance === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", appearance);
  }, [appearance]);
  if (error) return <main className="main narrow"><h1 className="title-l">Could not load the library</h1><p className="muted">{error}</p></main>;
  if (!store) return <main className="main narrow"><p className="muted">Loading the library…</p></main>;
  return (
    <StoreContext.Provider value={store}>
      <BrowserRouter>
        <ListenProvider>
          <AssistantProvider>
            <Shell />
          </AssistantProvider>
        </ListenProvider>
      </BrowserRouter>
    </StoreContext.Provider>
  );
}

createRoot(document.getElementById("root")!).render(<StrictMode><App /></StrictMode>);
