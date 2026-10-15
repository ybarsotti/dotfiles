const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WORK = path.join(ROOT, 'work', 'clips');
const OUT = path.join(ROOT, 'public', 'clips');
const W = 2880;
const H = 1800;
const FPS = 30;
const now = () => Date.now() / 1000;
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
const ease = (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2);

class Recorder {
  constructor(page, context) {
    this.page = page;
    this.context = context;
    this.cursor = { x: W / 2, y: H / 2 };
  }

  async start(name) {
    this.name = name;
    this.dir = path.join(WORK, name);
    fs.rmSync(this.dir, { recursive: true, force: true });
    fs.mkdirSync(this.dir, { recursive: true });
    this.frames = [];
    this.events = [];
    this.index = 0;
    this.cdp = await this.context.newCDPSession(this.page);
    this.cdp.on('Page.screencastFrame', async ({ data, metadata, sessionId }) => {
      const file = path.join(this.dir, `f${String(this.index).padStart(5, '0')}.jpg`);
      this.index += 1;
      fs.writeFileSync(file, Buffer.from(data, 'base64'));
      this.frames.push({ file, t: metadata.timestamp });
      await this.cdp.send('Page.screencastFrameAck', { sessionId }).catch(() => {});
    });
    await this.page.setViewportSize({ width: W, height: H });
    await sleep(300);
    this.t0 = now();
    await this.cdp.send('Page.startScreencast', { format: 'jpeg', quality: 95, maxWidth: W, maxHeight: H, everyNthFrame: 1 });
    this.log('cursor', this.cursor);
  }

  log(type, extra = {}) {
    this.events.push({ type, t: Number((now() - this.t0).toFixed(3)), ...extra });
  }

  async stop() {
    await sleep(600);
    this.log('end');
    await this.cdp.send('Page.stopScreencast').catch(() => {});
    await sleep(300);
    await this.cdp.detach().catch(() => {});
    const end = now();
    const frames = this.frames.filter((frame) => frame.t >= this.t0 - 0.05);
    const probe = execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v', '-show_entries', 'stream=width,height', '-of', 'csv=p=0', frames[frames.length - 1].file]).toString().trim();
    if (probe !== `${W},${H}`) throw new Error(`frame size ${probe}, expected ${W},${H}`);
    const concat = [];
    const ticks = Math.round((end - this.t0) * FPS);
    let cursor = 0;
    for (let tick = 0; tick < ticks; tick += 1) {
      const at = this.t0 + tick / FPS;
      while (cursor + 1 < frames.length && frames[cursor + 1].t <= at) cursor += 1;
      concat.push(`file '${frames[cursor].file}'`);
      concat.push(`duration ${(1 / FPS).toFixed(6)}`);
    }
    const list = path.join(this.dir, 'frames.txt');
    fs.writeFileSync(list, concat.join('\n') + '\n');
    fs.mkdirSync(OUT, { recursive: true });
    const mp4 = path.join(OUT, `${this.name}.mp4`);
    execFileSync('ffmpeg', [
      '-y', '-loglevel', 'error', '-f', 'concat', '-safe', '0', '-i', list,
      '-fps_mode', 'cfr', '-r', String(FPS), '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', mp4,
    ]);
    const meta = {
      name: this.name,
      width: W,
      height: H,
      fps: FPS,
      duration: Number((end - this.t0).toFixed(3)),
      firstFrameOffset: Number((frames[0].t - this.t0).toFixed(3)),
      frames: frames.length,
      events: this.events,
    };
    fs.writeFileSync(path.join(OUT, `${this.name}.json`), JSON.stringify(meta, null, 2));
    fs.rmSync(this.dir, { recursive: true, force: true });
    console.log(`CLIP ${this.name}: ${meta.duration}s, ${frames.length} frames`);
  }

  async abort() {
    await this.cdp?.send('Page.stopScreencast').catch(() => {});
    await this.cdp?.detach().catch(() => {});
    if (this.dir) fs.rmSync(this.dir, { recursive: true, force: true });
  }

  async glide(x, y, ms = 900) {
    const from = { ...this.cursor };
    const steps = Math.max(8, Math.round(ms / 16));
    for (let step = 1; step <= steps; step += 1) {
      const progress = ease(step / steps);
      const cx = from.x + (x - from.x) * progress;
      const cy = from.y + (y - from.y) * progress;
      await this.page.mouse.move(cx, cy);
      this.cursor = { x: cx, y: cy };
      if (step % 2 === 0 || step === steps) this.log('cursor', { x: Math.round(cx), y: Math.round(cy) });
      await sleep(16);
    }
  }

  async hover(locator, ms = 900, offset = { x: 0.5, y: 0.5 }) {
    const box = await locator.first().boundingBox();
    if (!box) throw new Error(`no box for ${locator}`);
    this.log('target', { x0: Math.round(box.x), y0: Math.round(box.y), x1: Math.round(box.x + box.width), y1: Math.round(box.y + box.height), label: locator.toString().slice(0, 120) });
    await this.glide(box.x + box.width * offset.x, box.y + box.height * offset.y, ms);
    return box;
  }

  async click(locator, ms = 900, offset = { x: 0.5, y: 0.5 }) {
    await this.hover(locator, ms, offset);
    await sleep(260);
    this.log('down', { x: Math.round(this.cursor.x), y: Math.round(this.cursor.y) });
    await this.page.mouse.down();
    await sleep(90);
    await this.page.mouse.up();
    this.log('up');
    await sleep(120);
  }

  async fixPoppers() {
    await sleep(350);
    await this.page.evaluate(() => {
      for (const el of document.querySelectorAll('[data-radix-popper-content-wrapper]')) {
        const match = /translate\(([-\d.]+)px,\s*([-\d.]+)px\)/.exec(el.style.transform || '');
        if (!match || el.dataset.fixed) continue;
        el.dataset.fixed = '1';
        let x = Number(match[1]) / 2;
        const y = Number(match[2]) / 2;
        el.style.transform = el.style.transform.replace(match[0], `translate(${x}px, ${y}px)`);
        const rect = el.getBoundingClientRect();
        const overflow = rect.right - window.innerWidth + 24;
        if (overflow > 0) {
          x -= overflow / 2;
          el.style.transform = el.style.transform.replace(/translate\([^)]*\)/, `translate(${x}px, ${y}px)`);
        }
      }
    });
    await sleep(250);
  }

  async type(text, delay = 95) {
    this.log('type-start', { text });
    await this.page.keyboard.type(text, { delay });
    this.log('type-end');
  }

  async hold(ms) {
    await sleep(ms);
  }
}

const film = async (steps, only) => {
  const { chromium } = require(steps.playwright);
  const browser = await chromium.launch({ executablePath: steps.chrome, args: [`--window-size=${W},${H}`] });
  const context = await browser.newContext({
    ignoreHTTPSErrors: true,
    viewport: { width: W, height: H },
    deviceScaleFactor: 1,
    locale: steps.locale ?? 'en-US',
    timezoneId: steps.timezoneId,
    storageState: steps.storageState,
  });
  const page = await context.newPage();
  await page.addInitScript(() => {
    const apply = () => {
      document.documentElement.style.zoom = '2';
      const style = document.createElement('style');
      style.textContent = 'nextjs-portal { display: none !important; } * { cursor: none !important; }';
      document.head.appendChild(style);
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', apply);
    else apply();
  });
  page.on('response', (r) => { if (r.status() >= 500) console.log('HTTP', r.status(), r.url()); });
  const rec = new Recorder(page, context);
  const open = async (p, wait = 7000) => {
    await page.goto(`${steps.base}${p}`, { waitUntil: 'domcontentloaded', timeout: 240000 });
    await page.waitForTimeout(wait);
    await page.evaluate(() => { document.documentElement.style.zoom = '2'; });
    await page.waitForTimeout(500);
  };
  for (const [name, run] of Object.entries(steps.clips)) {
    if (only.length > 0 && !only.includes(name)) continue;
    try {
      await run({ page, rec, open, W, H });
    } catch (error) {
      console.log(`FAIL ${name}: ${error.message.split('\n')[0]}`);
      fs.mkdirSync(path.join(ROOT, 'work'), { recursive: true });
      await page.screenshot({ path: path.join(ROOT, 'work', `fail-${name}.png`) }).catch(() => {});
      await rec.abort();
      process.exitCode = 1;
    }
  }
  await browser.close();
};

if (require.main === module) {
  const [stepsFile, ...only] = process.argv.slice(2);
  if (!stepsFile) {
    console.error('usage: node scripts/record.cjs <steps file> [clip name ...]');
    process.exit(2);
  }
  film(require(path.resolve(stepsFile)), only).catch((error) => { console.error('ERR', error.message); process.exit(1); });
}

module.exports = { Recorder, film, W, H, FPS };
