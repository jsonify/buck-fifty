// Renders the SVGs from make-icon.py to 1024 px PNGs with Playwright's Chromium.
//   node Scripts/render-icon.js <svg-dir> <png-dir>
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const [src, dst] = process.argv.slice(2);
  fs.mkdirSync(dst, { recursive: true });
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1024, height: 1024 }, deviceScaleFactor: 1 });
  for (const name of ['light', 'dark', 'tinted']) {
    const svg = fs.readFileSync(path.join(src, `icon-${name}.svg`), 'utf8');
    await page.setContent(`<html><body style="margin:0;background:#000">${svg}</body></html>`);
    await page.screenshot({ path: path.join(dst, `icon-${name}.png`), clip: { x: 0, y: 0, width: 1024, height: 1024 } });
  }
  await browser.close();
})();
