// Converts HTML-rendered real terminal captures to PNG.
// Usage: node shoot.mjs input.html output.png [input2.html output2.png ...]
// Several pairs are rendered in one browser session (used for animation frames).
import { createRequire } from "module";
const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require("playwright");
} catch {
  playwright = require(process.env.PLAYWRIGHT_MODULE || "/opt/node22/lib/node_modules/playwright");
}

const pairs = process.argv.slice(2);
if (pairs.length < 2 || pairs.length % 2 !== 0) {
  console.error("usage: node shoot.mjs input.html output.png [input2.html output2.png ...]");
  process.exit(2);
}
const browser = await playwright.chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
});
const page = await browser.newPage({ viewport: { width: 2000, height: 1200 }, deviceScaleFactor: 1 });
for (let i = 0; i < pairs.length; i += 2) {
  await page.goto("file://" + pairs[i]);
  await page.waitForTimeout(i === 0 ? 150 : 30);
  const el = await page.$("#term");
  await el.screenshot({ path: pairs[i + 1] });
}
await browser.close();
