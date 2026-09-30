// Xuất js/data.js ra JSON để server Elixir dùng chung một nguồn dữ liệu.
// Chạy lại mỗi khi sửa js/data.js: node tools/export-data.js
const fs = require('fs');
const path = require('path');
const data = require('../js/data.js');

const out = path.join(__dirname, '..', 'server', 'priv', 'game_data.json');
fs.writeFileSync(out, JSON.stringify(data, null, 2) + '\n');
console.log(`Đã tạo ${path.relative(path.join(__dirname, '..'), out)}`);
