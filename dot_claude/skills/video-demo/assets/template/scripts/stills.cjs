const { bundle } = require('@remotion/bundler');
const { renderStill, selectComposition } = require('@remotion/renderer');
const path = require('path');
const fs = require('fs');
const ROOT = path.resolve(__dirname, '..');
const specs = process.argv.slice(2).map((arg) => { const [name, frame] = arg.split('='); return { name, frame: Number(frame) }; });
(async () => {
  const serveUrl = await bundle({ entryPoint: path.join(ROOT, 'src/index.ts'), onProgress: () => {} });
  const composition = await selectComposition({ serveUrl, id: 'Tour' });
  fs.mkdirSync(path.join(ROOT, 'work/stills'), { recursive: true });
  for (const spec of specs) {
    const output = path.join(ROOT, 'work/stills', `${spec.name}.png`);
    await renderStill({ composition, serveUrl, output, frame: spec.frame, scale: 0.5, timeoutInMilliseconds: 120000 });
    console.log('STILL', spec.name, spec.frame);
  }
})().catch((error) => { console.error('ERR', error.message); process.exit(1); });
