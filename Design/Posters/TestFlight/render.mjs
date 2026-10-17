// Render the poster to a letter-size PDF and a PNG preview: node render.mjs (needs playwright)
import { chromium } from 'playwright';
import { fileURLToPath } from 'url';
import path from 'path';
const dir = path.dirname(fileURLToPath(import.meta.url));
const b = await chromium.launch();
const p = await b.newPage({ viewport: { width: 816, height: 1056 }, deviceScaleFactor: 2 });
await p.goto('file://' + path.join(dir, 'hot-mess-testflight-poster.html'), { waitUntil: 'networkidle' });
await p.evaluate(() => document.fonts.ready);
await p.pdf({ path: path.join(dir, 'hot-mess-testflight-poster.pdf'), width: '8.5in', height: '11in', printBackground: true, preferCSSPageSize: true });
await p.screenshot({ path: path.join(dir, 'hot-mess-testflight-poster-preview.png') });
await b.close();
