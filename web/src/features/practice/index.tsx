// Practice: flashcard decks and the games (port of FlashcardsView.swift and GamesView.swift).
import { useParams } from "react-router-dom";
import { SmartDeck } from "./flashcards";
import { MatchGame, SpeedRound, ZoomGuess } from "./games";
import { useBack } from "./shared";
import "./practice.css";

export { FlashcardsPage } from "./flashcards";
export { usePracticeBests } from "./progress";

/** /games/match | speed | zoom; anything else plays the Smart flashcard deck (like the iOS "game" deep link). */
export function GamePage() {
  const { game = "" } = useParams();
  const close = useBack("/quiz");
  switch (game) {
    case "match": return <MatchGame key="match" onClose={close} />;
    case "speed": return <SpeedRound key="speed" onClose={close} />;
    case "zoom": return <ZoomGuess key="zoom" onClose={close} />;
    default: return <SmartDeck key={game} onClose={close} />;
  }
}
