const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const CLIPS = path.join(ROOT, 'public', 'clips');
const meta = {};
const files = fs.existsSync(CLIPS) ? fs.readdirSync(CLIPS).filter((name) => name.endsWith('.json')).sort() : [];
for (const file of files) {
  const clip = JSON.parse(fs.readFileSync(path.join(CLIPS, file), 'utf8'));
  const mp4 = path.join(CLIPS, `${clip.name}.mp4`);
  const probe = execFileSync('ffprobe', ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', mp4]).toString().trim();
  clip.encodedDuration = Number(probe);
  const last = path.join(CLIPS, `${clip.name}-last.png`);
  execFileSync('ffmpeg', ['-y', '-loglevel', 'error', '-sseof', '-0.2', '-i', mp4, '-frames:v', '1', '-update', '1', last]);
  meta[clip.name] = clip;
  console.log(`${clip.name}: ${clip.duration}s recorded, ${clip.encodedDuration}s encoded, ${clip.events.filter((e) => e.type === 'target').length} targets`);
}
fs.writeFileSync(path.join(ROOT, 'src', 'clipMeta.json'), JSON.stringify(meta));
console.log(`${files.length} clip(s) -> src/clipMeta.json`);
