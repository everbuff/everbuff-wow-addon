// Screenshots and real-font measurements of the pages tests/render_html.lua writes.
//
// Usage (on a machine with Chrome, never next to a running WoW client):
//   npm install puppeteer-core            (once, in any folder on NODE_PATH or next to this script)
//   CHROME=/usr/bin/google-chrome node tests/render_shot.js <outdir>
// For every page in <outdir>/manifest.json it writes <page>.png and <page>.findings.json. The findings are measured
// in the browser with the addon's own fonts loaded:
//   cut              a single-line text wider than its width: the client shortens it with "..."
//   lines            a wrapped text that needs more lines than its box holds (it runs past its bottom)
//   exceeds-parent   the drawn text runs outside the frame it belongs to (a row, a card, a button)
//   zero-parent      the text belongs to a frame 2 px or less wide or high (a row with no width)
//   off-window       the drawn text runs outside the window
//   clipped          a scroll frame cuts the text at its left or right edge (the list is wider than its frame)
//   overlap          two visible texts drawn over each other by more than 2 px each way
// Texts scrolled out of a scroll frame are skipped, as the player cannot see them.
const fs = require('fs');
const path = require('path');
const puppeteer = require('puppeteer-core');

function measure() {
  const win = document.getElementById('win');
  const m = +win.dataset.margin;
  const W = +win.dataset.w, H = +win.dataset.h;
  const winBox = { l: m, t: m, r: m + W, b: m + H };
  const probe = document.createElement('span');
  probe.style.cssText = 'position:absolute;left:-10000px;top:0;white-space:pre;visibility:hidden;font-kerning:none;font-variant-ligatures:none';
  document.body.appendChild(probe);
  const inter = (a, b) => ({ l: Math.max(a.l, b.l), t: Math.max(a.t, b.t), r: Math.min(a.r, b.r), b: Math.min(a.b, b.b) });
  const empty = (a) => a.r - a.l <= 0.5 || a.b - a.t <= 0.5;
  const rect = (r) => ({ l: r.left, t: r.top, r: r.right, b: r.bottom });
  const round = (v) => Math.round(v * 10) / 10;
  const out = [];
  const visible = [];
  for (const el of document.querySelectorAll('#win .fs')) {
    const text = el.textContent;
    if (!text.trim()) continue;
    const cs = getComputedStyle(el);
    probe.style.fontFamily = cs.fontFamily; probe.style.fontSize = cs.fontSize;
    probe.innerHTML = el.innerHTML;
    const natural = probe.getBoundingClientRect().width;
    const box = rect(el.getBoundingClientRect());
    const range = document.createRange(); range.selectNodeContents(el);
    let drawn = rect(range.getBoundingClientRect());
    const nowrap = el.dataset.wrap === '0', fixedW = el.dataset.fixedw === '1';
    if (nowrap && fixedW) drawn = inter(drawn, box);
    // clip ancestors (scroll frames)
    let clipBox = { l: -1e9, t: -1e9, r: 1e9, b: 1e9 };
    for (let p = el.parentElement; p && p.id !== 'win'; p = p.parentElement) {
      if (p.classList.contains('clip')) clipBox = inter(clipBox, rect(p.getBoundingClientRect()));
    }
    const seen = inter(drawn, clipBox);
    if (empty(seen)) continue;
    const info = { text: text.slice(0, 80), src: el.dataset.src, box: [round(box.l - m), round(box.t - m), round(box.r - box.l), round(box.b - box.t)],
      font: cs.fontFamily.replace(/"/g, '') + ' ' + cs.fontSize };
    if (drawn.r > clipBox.r + 0.5 || drawn.l < clipBox.l - 0.5) out.push({ kind: 'clipped', hidden: round(Math.max(drawn.r - clipBox.r, clipBox.l - drawn.l)), ...info });
    if (nowrap && fixedW && natural > (box.r - box.l) + 0.5) out.push({ kind: 'cut', need: round(natural), has: round(box.r - box.l), ...info });
    if (!nowrap) {
      const lh = parseFloat(cs.lineHeight);
      const lines = Math.round((drawn.b - drawn.t) / lh);
      if (lines > +el.dataset.lines) out.push({ kind: 'lines', lines, planned: +el.dataset.lines, ...info });
    }
    if (el.dataset.pbox) {
      const [pl, pt, pw, ph] = el.dataset.pbox.split(',').map(Number);
      if (pw <= 2 || ph <= 2) out.push({ kind: 'zero-parent', parent: [round(pl - m), round(pt - m), pw, ph], ...info });
      else {
        const pr = { l: pl, t: pt, r: pl + pw, b: pt + ph };
        const over = { left: round(pr.l - seen.l), right: round(seen.r - pr.r), top: round(pr.t - seen.t), bottom: round(seen.b - pr.b) };
        if (over.left > 1 || over.right > 1 || over.top > 2 || over.bottom > 2) out.push({ kind: 'exceeds-parent', parent: [round(pl - m), round(pt - m), pw, ph], over, ...info });
      }
    }
    if (seen.r > winBox.r + 0.5 || seen.l < winBox.l - 0.5 || seen.b > winBox.b + 0.5) out.push({ kind: 'off-window', right: round(seen.r - winBox.r), ...info });
    visible.push({ el, seen, info });
  }
  for (let i = 0; i < visible.length; i++) {
    for (let j = i + 1; j < visible.length; j++) {
      const a = visible[i].seen, b = visible[j].seen;
      const ox = Math.min(a.r, b.r) - Math.max(a.l, b.l), oy = Math.min(a.b, b.b) - Math.max(a.t, b.t);
      if (ox > 2 && oy > 2) out.push({ kind: 'overlap', px: [round(ox), round(oy)], a: visible[i].info, b: visible[j].info });
    }
  }
  probe.remove();
  return { page: win.dataset.page, w: W, h: H, data: win.dataset.data, texts: visible.length, fontsLoaded: [...document.fonts].map(f => f.family + ':' + f.status), findings: out };
}

(async () => {
  const dir = path.resolve(process.argv[2] || 'tests/render_out');
  const pages = JSON.parse(fs.readFileSync(path.join(dir, 'manifest.json'), 'utf8'));
  const browser = await puppeteer.launch({ executablePath: process.env.CHROME || '/usr/bin/google-chrome', headless: 'new',
    args: ['--no-sandbox', '--allow-file-access-from-files', '--font-render-hinting=none'] });
  const page = await browser.newPage();
  for (const p of pages) {
    await page.setViewport({ width: p.w, height: p.h, deviceScaleFactor: 1 });
    await page.goto('file://' + path.join(dir, p.name + '.html'), { waitUntil: 'load' });
    await page.evaluate(async () => { await Promise.all([...document.fonts].map(f => f.load())); await document.fonts.ready; });
    await page.screenshot({ path: path.join(dir, p.name + '.png') });
    const res = await page.evaluate(measure);
    fs.writeFileSync(path.join(dir, p.name + '.findings.json'), JSON.stringify(res, null, 1));
    const kinds = {};
    for (const f of res.findings) kinds[f.kind] = (kinds[f.kind] || 0) + 1;
    console.log(p.name.padEnd(40), JSON.stringify(kinds));
  }
  await browser.close();
})().catch((e) => { console.error(e); process.exit(1); });
