// QuizState.swift on the web: spaced repetition, points and streaks in localStorage ("quiz.v1").
import { useMemo } from "react";
import { useLocal } from "../../store";
import {
  accuracy, dayKey, EMPTY_SNAPSHOT, isDue, isMastered, needsReview, pointsFor, recordAnswer, recordFinish, streak,
  type QuizItem, type QuizKind, type QuizSnapshot,
} from "./engine";

export const QUIZ_KEY = "quiz.v1";

/** Fills in fields missing from older or hand-edited saves. */
const normalize = (s: Partial<QuizSnapshot> | null | undefined): QuizSnapshot => ({
  ...EMPTY_SNAPSHOT,
  ...(s && typeof s === "object" ? s : {}),
  records: s?.records && typeof s.records === "object" ? s.records : {},
  activeDays: Array.isArray(s?.activeDays) ? s!.activeDays : [],
});

export function useQuizState() {
  const [raw, setRaw] = useLocal<QuizSnapshot>(QUIZ_KEY, EMPTY_SNAPSHOT);
  return useMemo(() => {
    const snapshot = normalize(raw);
    const update = (f: (s: QuizSnapshot) => QuizSnapshot) => setRaw((old) => f(normalize(old)));
    const answered = Object.values(snapshot.records).reduce((n, r) => n + r.seen, 0);
    return {
      snapshot,
      record: (id: string) => snapshot.records[id],
      answer: (item: QuizItem, correct: boolean) => update((s) => recordAnswer(s, item.id, correct, pointsFor(item))),
      /** Records an answer from any practice mode in the same spaced-repetition boxes. */
      mark: (id: string, correct: boolean, points = 10) => update((s) => recordAnswer(s, id, correct, points)),
      /** Bonus points without touching review boxes. */
      award: (points: number) => update((s) => ({ ...s, xp: s.xp + Math.max(0, points) })),
      /** A finished practice session counts towards the streak. */
      practiced: () => update((s) => (s.activeDays.includes(dayKey()) ? s : { ...s, activeDays: [...s.activeDays, dayKey()] })),
      finish: (kind: QuizKind) => update((s) => recordFinish(s, kind)),
      reset: () => setRaw(EMPTY_SNAPSHOT),
      dailyDoneToday: snapshot.dailyDone === dayKey(),
      xp: snapshot.xp,
      streak: streak(snapshot),
      answeredCount: answered,
      accuracy: accuracy(snapshot),
      isMastered: (id: string) => isMastered(snapshot, id),
      isDue: (id: string) => isDue(snapshot, id),
      needsReview: (id: string) => needsReview(snapshot, id),
    };
  }, [raw, setRaw]);
}

export type QuizState = ReturnType<typeof useQuizState>;
