"""Build the mini-book library and check its expected 41 illustrated pages."""
import html
import json
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parent
EXPECTED = [
    ('00-field-guide', 'Fellowship research field guide', 3, 'Start here'),
    ('01-eval-gaming', 'Eval gaming under training pressure', 4, 'Candidate'),
    ('02-sandbagging-benchmark', 'A sandbagging auditing benchmark', 4, 'Candidate'),
    ('03-training-run-toolkit', 'Training-run evaluation toolkit', 4, 'Candidate'),
    ('04-reward-hacking-generalization', 'What makes reward hacking generalize', 4, 'Candidate'),
    ('05-stacked-lie-detectors', 'Stacked lie detectors under evasion', 4, 'Candidate'),
    ('06-rl-monitorability', 'The monitorability cost of ordinary RL', 4, 'Candidate'),
    ('07-monitors-across-agents', 'Monitors that see across agents', 4, 'Candidate'),
    ('08-introspection-adapters', 'Stress-testing introspection adapters', 4, 'Candidate'),
    ('09-latent-reasoner-probes', 'RL against probes in latent reasoners', 4, 'Candidate'),
    ('10-introspection-foundation', 'Training introspection that generalizes', 2, 'Completed foundation'),
]
books, missing, duplicates = [], [], []
readme = ['# Anthropic Fellowship Project Comics', '',
    'Nine candidate projects, one completed-work foundation, and a shared research field guide. Each candidate gets four illustrated pages explaining the question, experiment, measurements, confounds, and four-month plan. The foundation gets two pages. This independent study collection follows the repository’s comic style, with 4–10 panels per page and visible acronym definitions.', '',
    'Open [the book library](index.html). The collection has 41 portrait PNG pages, arranged in reading order below. Exact generation and repair prompts are in `prompts/`; primary research links and caveats are in `notes/`.', '',
    'The [supplied project map](source/fellowship-project-map-2026-10-11.txt) is dated 11 October 2026. Budgets are planning estimates. Novelty labels, proposed tooling and researcher fit need rechecking before a pitch. Researcher names do not establish confirmed mentorship. These comics are not an official Anthropic publication.', '']
for folder, title, count, status in EXPECTED:
    directory = ROOT / folder
    meta = json.loads((directory / 'book.json').read_text()) if (directory / 'book.json').exists() else {}
    pages = []
    for n in range(1, count + 1):
        matches = sorted(directory.glob(f'{n:02d}-*.png'))
        if len(matches) > 1:
            duplicates.append(f'{folder}/{n:02d}')
        if not matches:
            missing.append(f'{folder}/{n:02d}')
            continue
        file = matches[0]
        metadata = next((p for p in meta.get('pages', []) if p.get('number') == n), {})
        page_title = metadata.get('title') or file.stem[3:].replace('-', ' ').title()
        pages.append({'number': n, 'title': page_title, 'image': str(file.relative_to(ROOT))})
    books.append({'id': folder, 'title': title, 'status': status, 'expected': count, 'pages': pages})
    readme.extend([f'## {title}', '', f'{status} · {count} pages', ''])
    readme.extend(f"{p['number']}. [{p['title']}]({quote(p['image'])})" for p in pages)
    readme.append('')
(ROOT / 'manifest.json').write_text(json.dumps(books, indent=2, ensure_ascii=False) + '\n')
(ROOT / 'README.md').write_text('\n'.join(readme) + '\n')
cards = []
for b in books:
    cover = f'<img src="{quote(b["pages"][0]["image"])}" alt="" loading="lazy">' if b['pages'] else '<div class="placeholder">In production</div>'
    cards.append(f'<button class="book" data-book="{b["id"]}">{cover}<div><small>{html.escape(b["status"])} · {b["expected"]} pages</small><h2>{html.escape(b["title"])}</h2><span>Read this book →</span></div></button>')
data = json.dumps(books, ensure_ascii=False).replace('<', '\\u003c')
page = '''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Fellowship Project Comic Library</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#05090b;color:#f2eedf;font:16px system-ui,sans-serif}button,a{touch-action:manipulation}button{font:inherit;cursor:pointer}header{max-width:1200px;margin:auto;padding:48px 24px 24px}.eyebrow{color:#16d9ef;font-size:13px;letter-spacing:.14em;text-transform:uppercase}h1{font-size:clamp(34px,5vw,64px);line-height:1.04;letter-spacing:-.04em;margin:14px 0}header p{max-width:760px;line-height:1.65;color:#afc3c8}a{color:#16d9ef}.library{max-width:1200px;margin:auto;padding:16px 24px 56px;display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:24px}.book{text-align:left;background:#0d191e;border:1px solid #29505c;border-radius:14px;overflow:hidden;color:inherit;padding:0;transition:transform .15s,border-color .15s}.book:hover{transform:translateY(-4px);border-color:#16d9ef}.book img{display:block;width:100%;aspect-ratio:2/3;object-fit:contain;background:#000}.book>div{padding:20px}.book small{color:#a9d52b}.book h2{font-size:20px;line-height:1.3;margin:8px 0 16px}.book span{color:#16d9ef}.placeholder{aspect-ratio:2/3;display:grid;place-items:center}.reader{max-width:1200px;margin:auto;padding:24px}.reader-head{display:flex;align-items:center;gap:12px;flex-wrap:wrap}.reader-head h1{font-size:clamp(25px,4vw,42px);flex:1}.controls{display:flex;align-items:center;justify-content:center;gap:16px;margin:18px 0;flex-wrap:wrap}button.control{border:1px solid #2e606d;background:#11252c;color:#f2eedf;border-radius:8px;padding:11px 18px}button:disabled{opacity:.35;cursor:default}.page-image{display:block;width:100%;max-width:1024px;margin:auto;height:auto;border:1px solid #284d57;border-radius:6px}.page-title{text-align:center;color:#b4ced4}.reader-foot{text-align:center;margin:20px}.note{max-width:1152px;margin:0 auto 40px;padding:20px 24px;border-top:1px solid #24444d;color:#95afb7;font-size:14px;line-height:1.6}.note p{max-width:900px}a:focus-visible,button:focus-visible{outline:3px solid #f5be32;outline-offset:4px}[hidden]{display:none!important}
</style></head><body>
<div id="shelf"><header><span class="eyebrow">Independent study collection · 41 illustrated pages</span><h1>Fellowship Project<br>Comic Library</h1><p>Nine research candidates, explained from the first analogy to the actual experiment. Start with the field guide, then open a mini-book to study its measurements, controls, and four-month plan.</p></header><main class="library">BOOK_CARDS</main><footer class="note"><p>Based on your project map dated 11 October 2026. Budgets and proposed schedules are planning estimates; novelty and tooling need rechecking. This is an independent learning aid, not an official Anthropic publication.</p><a href="README.md">Complete page list</a> · <a href="source/fellowship-project-map-2026-10-11.txt">Original project map</a></footer></div>
<main id="reader" class="reader" hidden><div class="reader-head"><button class="control" id="back">← All books</button><h1 id="book-title"></h1></div><div class="controls"><button class="control" id="prev">← Previous page</button><span id="position" aria-live="polite"></span><button class="control" id="next">Next page →</button></div><p id="page-title" class="page-title"></p><a id="full-image" target="_blank" rel="noopener"><img id="page-image" class="page-image" alt=""></a><div class="reader-foot"><a id="download" download>Download this page</a><p>Click the image to open it at full size. Use ← and → to turn pages.</p></div></main>
<script>
const books=BOOK_DATA;let active=null,pageIndex=0;
const shelf=document.querySelector('#shelf'),reader=document.querySelector('#reader');
function path(p){return p.split('/').map(encodeURIComponent).join('/')}
function route(){const parts=decodeURIComponent(location.hash.slice(1)).split('/');active=books.find(b=>b.id===parts[0]);pageIndex=Math.max(0,(parseInt(parts[1],10)||1)-1);if(!active||!active.pages.length){reader.hidden=true;shelf.hidden=false;return}pageIndex=Math.min(pageIndex,active.pages.length-1);const p=active.pages[pageIndex],src=path(p.image);shelf.hidden=true;reader.hidden=false;document.querySelector('#book-title').textContent=active.title;document.querySelector('#position').textContent='Page '+p.number+' of '+active.expected;document.querySelector('#page-title').textContent=p.title;const im=document.querySelector('#page-image');im.src=src;im.alt=active.title+' — page '+p.number+': '+p.title;document.querySelector('#full-image').href=src;document.querySelector('#download').href=src;document.querySelector('#prev').disabled=pageIndex===0;document.querySelector('#next').disabled=pageIndex===active.pages.length-1;window.scrollTo(0,0)}
function move(d){if(active&&pageIndex+d>=0&&pageIndex+d<active.pages.length)location.hash=active.id+'/'+(pageIndex+d+1)}
document.querySelectorAll('[data-book]').forEach(b=>b.addEventListener('click',()=>location.hash=b.dataset.book+'/1'));document.querySelector('#back').onclick=()=>location.hash='';document.querySelector('#prev').onclick=()=>move(-1);document.querySelector('#next').onclick=()=>move(1);window.addEventListener('hashchange',route);window.addEventListener('keydown',e=>{if(!active)return;if(e.key==='ArrowLeft')move(-1);if(e.key==='ArrowRight')move(1);if(e.key==='Escape')location.hash=''});route();
</script></body></html>'''
page = page.replace('BOOK_CARDS', ''.join(cards)).replace('BOOK_DATA', data)
(ROOT / 'index.html').write_text(page)
print(json.dumps({'expected': 41, 'saved': sum(len(b['pages']) for b in books), 'missing': missing, 'duplicates': duplicates}, indent=2))
