// Converts an HTML-rendered real terminal capture to PNG.
// Usage: node shoot.mjs input.html output.png
import { createRequire } from "module";
const require = createRequire(import.meta.url);
let playwright;
try {
  playwright = require("playwright");
} catch {
  playwright = require(process.env.PLAYWRIGHT_MODULE || "/opt/node22/lib/node_modules/playwright");
}

const [, , input, output] = process.argv;
const browser = await playwright.chromium.launch({
  executablePath: process.env.CHROMIUM_PATH || undefined,
});
const page = await browser.newPage({ viewport: { width: 2000, height: 1200 }, deviceScaleFactor: 1 });
await page.goto("file://" + input);
await page.waitForTimeout(150);
const el = await page.$("#term");
await el.screenshot({ path: output });
await browser.close();
