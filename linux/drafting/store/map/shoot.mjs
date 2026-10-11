// Renders one map background: the app's own style, with an itinerary's legs
// and stops drawn the way the journey map draws them.
//
//   node shoot.mjs SPEC.json OUT.png WIDTH HEIGHT PADDING_JSON MAX_ZOOM
import fs from 'fs';
import { createRequire } from 'module';

// CommonJS resolution, so NODE_PATH can point at a global install.
const { chromium } = createRequire(import.meta.url)('playwright');

const [, , specPath, out, w, h, padJson, maxZoom] = process.argv;
const style = JSON.parse(
  fs.readFileSync(new URL('../../../../assets/styles/default.json', import.meta.url)),
);
const spec = JSON.parse(fs.readFileSync(specPath));
const browser = await chromium.launch({
  args: ['--use-gl=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'],
});
const page = await browser.newPage({ viewport: { width: +w, height: +h }, deviceScaleFactor: 2 });
await page.goto('file://' + new URL('./map.html', import.meta.url).pathname);
await page.evaluate(
  ([s, sp, pad, mz]) => window.render(s, sp, pad, mz),
  [style, spec, JSON.parse(padJson), +maxZoom],
);
await page.screenshot({ path: out });
await browser.close();
