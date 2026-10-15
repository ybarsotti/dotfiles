// Steps for scripts/record.cjs. Copy this file to scripts/steps.cjs, keep the shape, and
// replace the clips with the flows of your feature:
//   node scripts/record.cjs scripts/steps.cjs            records every clip
//   node scripts/record.cjs scripts/steps.cjs 02-save    records one clip
// Each clip gets `{ page, rec, open, W, H }`: `rec.start(name)` begins the screencast, `rec.click`,
// `rec.hover`, `rec.type` and `rec.hold` drive the page while they log the cursor, the clicks and
// every target box, and `rec.stop()` encodes public/clips/<name>.mp4 and public/clips/<name>.json.
const path = require('path');

const row = (page, name) => page.getByRole('row', { name: new RegExp(name) });

module.exports = {
  playwright: '/path/to/a/project/node_modules/@playwright/test',
  // Optional. Omit it to use the browser that Playwright installed.
  chrome: '/path/to/Google Chrome for Testing',
  // A logged-in session saved with Playwright `context.storageState()`. Omit it for a public page.
  storageState: path.resolve(__dirname, '../work/state.json'),
  base: 'https://app.example.local',
  // Optional: `locale` (default 'en-US') and `timezoneId` (default: this machine's zone) for dates on screen.
  locale: 'en-US',
  clips: {
    '01-list': async ({ page, rec, open, W, H }) => {
      await open('/tasks', 9000);
      await page.mouse.move(W / 2, H / 2);
      await rec.start('01-list');
      await rec.hold(900);
      await rec.click(page.getByPlaceholder('Search...'), 1100);
      await rec.type('launch');
      await rec.hold(3500);
      await rec.hover(row(page, 'Write launch notes'), 900, { x: 0.45, y: 0.5 });
      await rec.hold(2000);
      await rec.stop();
    },
    '02-save': async ({ page, rec }) => {
      await rec.start('02-save');
      await rec.hold(500);
      await rec.click(page.getByRole('button', { name: 'Save view' }), 1000);
      await rec.fixPoppers();
      await rec.click(page.getByLabel('Name'), 800);
      await rec.type('My open tasks');
      await rec.click(page.getByRole('button', { name: 'Save' }), 900);
      await rec.hold(2500);
      await rec.stop();
    },
  },
};
