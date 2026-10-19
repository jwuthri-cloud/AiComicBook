# Safety Atlas: website

The iOS app's library on the web: reader (comic, text with Beginner/Advanced, video), glossary with concept map, Playbook (toolkit, experiment maps, drill), quiz with spaced repetition, flashcards and games, search, listen mode and the optional Ask assistant (the reader's own OpenAI key, kept only in their browser).

Vite + React + TypeScript, no backend. Progress lives in each browser's localStorage.

## Build

```bash
# 1. Content: same pipeline as the app, plus a web export (WebP pages, H.264 clips)
python3 app/tools/build_content.py --web web/public/content

# 2. Site
cd web && npm install && npm run dev        # http://localhost:5173
npm run build                               # → web/dist
```

`web/public/content/` is generated (≈350 MB) and gitignored, so deploy from a machine that ran step 1.

## Deploy (Vercel)

```bash
cd web
npx vercel login                 # once
npx vercel build --prod
npx vercel deploy --prebuilt --prod
```

`vercel.json` sends every route to `index.html` (client-side routing) and caches media for a week.

## Layout

- `src/content.ts` — content types, loader, term matcher (shared)
- `src/store.ts` — localStorage hooks: settings, progress, bookmarks (shared)
- `src/ui.tsx`, `src/theme.css` — shared components and the calm theme
- `src/pages/` — library, book, reader, Watch, settings
- `src/features/` — glossary, practice, quiz, playbook, search, listen, assistant
