/* Hình nhân vật ghép từ nhiều lớp (bộ tile Dungeon Crawl, assets/doll): thân, quần, giày,
 * giáp, tóc theo lớp nhân vật, vũ khí, khiên. `look` do server gửi (Engine.look):
 * { hair, weapon, armor, shield, pet } với mỗi lớp là đường dẫn trong assets/doll.
 *
 * Doll.canvas(look) trả về canvas 32×32 đã ghép (null khi hình chưa tải xong);
 * Doll.url(look) trả về ảnh dạng data URL để dùng trong <img>, tạm dùng hình mặc định khi
 * chưa xong. Tải xong thì gọi các hàm đăng ký bằng Doll.onReady để vẽ lại. */
(function () {
  const BASE = ['base/human_m', 'legs/pants_black', 'boots/short_brown2'];
  const FALLBACK = 'assets/monsters/hero.png';
  const images = {}, done = {}, urls = {};
  const listeners = [];
  let notifyTimer = null;

  const layers = (look) => BASE.concat([look && look.armor, look && look.hair, look && look.weapon, look && look.shield].filter(Boolean));
  const key = (look) => layers(look).join('|');

  function image(path) {
    if (!images[path]) {
      const im = new Image();
      im.onload = () => {
        // gom nhiều hình tải xong gần nhau thành một lần vẽ lại
        if (!notifyTimer) notifyTimer = setTimeout(() => { notifyTimer = null; listeners.forEach((f) => f()); }, 30);
      };
      im.src = 'assets/doll/' + path + '.png';
      images[path] = im;
    }
    return images[path];
  }

  function canvas(look) {
    const k = key(look);
    if (done[k]) return done[k];
    const ims = layers(look).map(image);
    if (!ims.every((im) => im.complete && im.naturalWidth)) return null;
    const c = document.createElement('canvas');
    c.width = 32; c.height = 32;
    const g = c.getContext('2d');
    ims.forEach((im) => g.drawImage(im, 0, 0));
    done[k] = c;
    return c;
  }

  function url(look) {
    const k = key(look);
    if (urls[k]) return urls[k];
    const c = canvas(look);
    if (!c) return FALLBACK;
    urls[k] = c.toDataURL();
    return urls[k];
  }

  window.Doll = { canvas, url, onReady: (f) => listeners.push(f) };
})();
