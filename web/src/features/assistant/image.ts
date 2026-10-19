// JPEG data URLs for vision input, downscaled so a comic page or photo stays small but readable
// (port of AssistantSession.dataURL).
import { url } from "../../content";

export async function jpegDataURL(source: string | Blob, maxSide = 1280, quality = 0.75): Promise<string> {
  const src = typeof source === "string" ? source : URL.createObjectURL(source);
  try {
    const img = new Image();
    img.src = src;
    await img.decode();
    const scale = Math.min(1, maxSide / Math.max(img.naturalWidth, img.naturalHeight, 1));
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(img.naturalWidth * scale));
    canvas.height = Math.max(1, Math.round(img.naturalHeight * scale));
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("No canvas");
    ctx.fillStyle = "#fff"; // transparent PNGs would turn black in JPEG
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
    return canvas.toDataURL("image/jpeg", quality);
  } finally {
    if (typeof source !== "string") URL.revokeObjectURL(src);
  }
}

const comicCache = new Map<string, Promise<string | undefined>>();

/** The comic page image for the model: a data URL, or the public https URL if conversion fails. */
export function comicImage(imagePath: string): Promise<string | undefined> {
  let hit = comicCache.get(imagePath);
  if (!hit) {
    hit = jpegDataURL(url(imagePath)).catch(() =>
      window.location.protocol === "https:" ? new URL(url(imagePath), window.location.href).href : undefined,
    );
    comicCache.set(imagePath, hit);
  }
  return hit;
}
