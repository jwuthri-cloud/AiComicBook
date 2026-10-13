"""Build a local browsing index and check one card per requested topic."""
import html
import json
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent
TOPICS = json.loads((ROOT / 'topics.json').read_text())
FOLDERS = ['01-training-fine-tuning', '02-core-alignment-theory', '03-failure-modes', '04-interpretability', '05-oversight-control', '06-evals-red-teaming', '07-policy-anthropic']
manifest, missing, duplicates = [], [], []
for (category, topics), folder in zip(TOPICS.items(), FOLDERS):
    for number, title in enumerate(topics, 1):
        files = sorted((ROOT / folder).glob(f'{number:02d}-*.png'))
        if len(files) > 1:
            duplicates.append(f'{folder}/{number:02d}')
        card = {'category': category, 'number': number, 'topic': title, 'image': str(files[0].relative_to(ROOT)) if files else None}
        manifest.append(card)
        if not files:
            missing.append(title)
(ROOT / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + '\n')

readme = ['# AI Safety Comic Cards', '', 'One illustrated card per requested topic, using plain-language explanations, analogies, mechanisms, examples, and caveats. Layouts vary from 4 to 10 panels, with more room for broader topics.', '', 'Open [the searchable gallery](index.html) to browse the collection. Full-resolution PNGs are organized below. Exact prompts are in `prompts/`; primary sources and production notes are in `notes/`.', '', 'Generated using the built-in image-generation tool. Research and policy checked October 12, 2026. Policy cards distinguish current RSP wording from earlier frameworks. Hypothetical risks and controlled research examples are labeled as such.', '']
for category, folder in zip(TOPICS, FOLDERS):
    readme += [f'## {category}', '']
    for card in [c for c in manifest if c['category'] == category]:
        readme.append(f"- [{card['topic']}]({quote(card['image'])})" if card['image'] else f"- {card['topic']} — generating")
    readme.append('')
(ROOT / 'README.md').write_text('\n'.join(readme) + '\n')

items = []
for c in manifest:
    if c['image']:
        items.append(f'<a class="card" href="{quote(c["image"])}" data-search="{html.escape(c["category"] + " " + c["topic"], quote=True)}"><img src="{quote(c["image"])}" loading="lazy" alt="{html.escape(c["topic"], quote=True)}"><div><small>{html.escape(c["category"])}</small><h2>{html.escape(c["topic"])}</h2></div></a>')
    else:
        items.append(f'<div class="card pending" data-search="{html.escape(c["category"] + " " + c["topic"], quote=True)}"><div><small>{html.escape(c["category"])}</small><h2>{html.escape(c["topic"])}</h2><p>Generating</p></div></div>')
page = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>AI Safety Comic Cards</title>
<style>*{box-sizing:border-box}body{margin:0;background:#05090b;color:#f2eedf;font:16px system-ui,sans-serif}header{padding:40px max(24px,5vw) 24px;border-bottom:1px solid #17444a}h1{font-size:clamp(32px,5vw,64px);margin:0 0 12px;letter-spacing:-.04em}header p{max-width:760px;line-height:1.6;color:#a9bdc1}.tools{display:flex;gap:12px;flex-wrap:wrap;padding:24px max(24px,5vw)}input,select{padding:13px 16px;background:#101c21;border:1px solid #29616b;border-radius:8px;color:#f2eedf;font:inherit}input{min-width:260px;flex:1}#count{padding:0 max(24px,5vw);color:#16d9ef}.grid{padding:24px max(24px,5vw) 64px;display:grid;grid-template-columns:repeat(auto-fill,minmax(250px,1fr));gap:24px}.card{display:block;text-decoration:none;color:inherit;background:#0d171b;border:1px solid #24444d;border-radius:12px;overflow:hidden;transition:transform .15s,border-color .15s}.card:hover{transform:translateY(-4px);border-color:#16d9ef}.card img{display:block;width:100%;height:auto;aspect-ratio:2/3;object-fit:contain}.card div{padding:16px}.card h2{font-size:18px;line-height:1.3;margin:6px 0 0}.card small{color:#a4c8d0}.pending{min-height:160px;border-style:dashed}.pending p{color:#f5be32}a:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid #f5be32;outline-offset:4px}[hidden]{display:none!important}</style>
<header><h1>AI Safety Comic Cards</h1><p>Big ideas, explained simply. Browse one illustrated card per topic, open the full image, and follow the analogies, mechanisms, examples, and caveats.</p></header>
<div class="tools"><input id="search" aria-label="Search topics" placeholder="Search a topic…"><select id="category" aria-label="Filter category"><option value="">All categories</option>OPTIONS</select></div><div id="count" aria-live="polite"></div><main class="grid">CARDS</main>
<script>const search=document.querySelector('#search'),select=document.querySelector('#category'),cards=[...document.querySelectorAll('.card')];function filter(){let n=0;for(const c of cards){const text=c.dataset.search.toLowerCase();const ok=text.includes(search.value.toLowerCase())&&(!select.value||c.dataset.search.startsWith(select.value+' '));c.hidden=!ok;if(ok)n++}document.querySelector('#count').textContent=n+' topics'}search.addEventListener('input',filter);select.addEventListener('change',filter);filter();</script></html>'''
page = page.replace('OPTIONS', ''.join(f'<option value="{html.escape(c, quote=True)}">{html.escape(c)}</option>' for c in TOPICS)).replace('CARDS', ''.join(items))
(ROOT / 'index.html').write_text(page)
print(json.dumps({'requested': len(manifest), 'saved': sum(c['image'] is not None for c in manifest), 'missing': missing, 'duplicates': duplicates}, indent=2))
