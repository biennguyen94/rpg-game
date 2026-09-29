// Gộp game thành một file HTML duy nhất (CSS, JS và ảnh nhúng sẵn).
// Dùng để đăng lên Claude Artifact hoặc gửi cho người khác chơi thử.
// Chạy: node tools/build.js  → dist/hac-long.html
const fs = require('fs');
const path = require('path');
const root = path.join(__dirname, '..');
const read = (p) => fs.readFileSync(path.join(root, p), 'utf8');

const assets = {};
for (const dir of ['monsters', 'icons', 'floors']) {
  for (const f of fs.readdirSync(path.join(root, 'assets', dir))) {
    const buf = fs.readFileSync(path.join(root, 'assets', dir, f));
    const mime = f.endsWith('.svg') ? 'image/svg+xml' : 'image/png';
    assets[`${dir}/${f}`] = `data:${mime};base64,${buf.toString('base64')}`;
  }
}

const html = read('index.html');
const between = (a, b) => html.split(a)[1].split(b)[0];
const head = between('<!--BUILD:HEAD-->', '<!--/BUILD:HEAD-->')
  .replace('<link rel="stylesheet" href="css/style.css">', `<style>\n${read('css/style.css')}\n</style>`);
const body = between('<!--BUILD:BODY-->', '<!--/BUILD:BODY-->')
  .replace(/<script src="(js\/[^"]+)"><\/script>/g, (_, src) => `<script>\n${read(src)}\n</script>`)
  .replace('<script>', `<script>window.ASSET_DATA=${JSON.stringify(assets)};</script>\n<script>`);

fs.mkdirSync(path.join(root, 'dist'), { recursive: true });
const out = path.join(root, 'dist', 'hac-long.html');
fs.writeFileSync(out, head.trim() + '\n' + body.trim() + '\n');
console.log(`Đã tạo ${path.relative(root, out)} (${Math.round(fs.statSync(out).size / 1024)} KB)`);
