// Copies the narrated clips into public/content/videos before building. They are not committed under web/
// (their sources already are, in "anthropic fellowship/videos/"), so this keeps the repo from storing them twice.
import { copyFileSync, existsSync, mkdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const web = join(dirname(fileURLToPath(import.meta.url)), "..");
const repo = join(web, "..");
const map = JSON.parse(readFileSync(join(web, "video-sources.json"), "utf8"));
let copied = 0;
for (const [dest, src] of Object.entries(map)) {
  const target = join(web, "public", "content", dest);
  if (existsSync(target)) continue;
  mkdirSync(dirname(target), { recursive: true });
  copyFileSync(join(repo, src), target);
  copied++;
}
console.log(`videos: ${copied} copied, ${Object.keys(map).length} total`);
