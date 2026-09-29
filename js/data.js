/* Dữ liệu game: lớp nhân vật, khu vực, quái vật, vật phẩm.
 * Chỉ số quái được sinh từ cấp độ (xem Engine.makeMonster), ở đây chỉ khai báo
 * cấp, hệ số sức mạnh (mult) và kỹ năng đặc biệt của trùm. */
(function (root) {
  const CLASSES = {
    warrior: {
      name: 'Chiến Binh',
      desc: 'Sát thương cao, trâu bò. Dễ chơi nhất.',
      icon: 'crossed-swords',
      base: { str: 8, vit: 7, agi: 4, def: 5 },
      growth: { str: 3, vit: 1, agi: 0, def: 0 },
      skill: { id: 'cleave', name: 'Chém Cuồng Nộ', desc: 'Gây 220% sát thương.', icon: 'sword-spin', cooldown: 3 },
    },
    rogue: {
      name: 'Thích Khách',
      desc: 'Nhanh nhẹn, hay chí mạng và né đòn.',
      icon: 'backstab',
      base: { str: 6, vit: 6, agi: 9, def: 4 },
      growth: { str: 1, vit: 0, agi: 3, def: 0 },
      skill: { id: 'backstab', name: 'Đâm Lén', desc: 'Chắc chắn chí mạng, xuyên 50% giáp.', icon: 'backstab', cooldown: 3 },
    },
    knight: {
      name: 'Hiệp Sĩ',
      desc: 'Phòng thủ vững, tự hồi máu.',
      icon: 'visored-helm',
      base: { str: 6, vit: 8, agi: 3, def: 7 },
      growth: { str: 2, vit: 1, agi: 0, def: 1 },
      skill: { id: 'holy', name: 'Khiên Thánh', desc: 'Gây 130% sát thương và hồi 25% máu.', icon: 'shield-reflect', cooldown: 4 },
    },
  };

  // Mỗi khu có quái thường và một trùm. Hạ trùm để mở khu tiếp theo.
  const ZONES = [
    {
      id: 'forest', name: 'Rừng Mê', icon: 'forest', levels: '1–5',
      desc: 'Khu rừng ngay ngoài làng. Nơi tốt để tập luyện.',
      monsters: [
        { id: 'bat', name: 'Dơi Hang', level: 1, mult: 0.8 },
        { id: 'jackal', name: 'Chó Rừng', level: 2 },
        { id: 'giant_cockroach', name: 'Gián Khổng Lồ', level: 3 },
        { id: 'spider', name: 'Nhện Độc', level: 4 },
      ],
      boss: { id: 'wolf', name: 'Sói Xám Đầu Đàn', level: 6, special: { name: 'Tru Trăng', every: 3, mult: 1.8 } },
    },
    {
      id: 'camp', name: 'Trại Goblin', icon: 'hill-fort', levels: '6–11',
      desc: 'Bọn goblin và orc dựng trại trên đồi.',
      monsters: [
        { id: 'kobold', name: 'Kobold', level: 6 },
        { id: 'goblin', name: 'Goblin', level: 7 },
        { id: 'gnoll', name: 'Gnoll', level: 8 },
        { id: 'hobgoblin', name: 'Hobgoblin', level: 9 },
        { id: 'orc', name: 'Orc', level: 10 },
      ],
      boss: { id: 'orc_warrior', name: 'Tướng Orc', level: 12, special: { name: 'Bổ Rìu', every: 3, mult: 2.0 } },
    },
    {
      id: 'graveyard', name: 'Nghĩa Địa Cổ', icon: 'dungeon-gate', levels: '12–17',
      desc: 'Người chết không yên nghỉ ở đây.',
      monsters: [
        { id: 'skeletal_warrior', name: 'Chiến Binh Xương', level: 12 },
        { id: 'ghoul', name: 'Quỷ Ăn Xác', level: 13 },
        { id: 'wight', name: 'Hồn Ma Mộ', level: 15 },
        { id: 'vampire', name: 'Ma Cà Rồng', level: 16 },
      ],
      boss: { id: 'lich', name: 'Pháp Sư Bất Tử', level: 18, special: { name: 'Lửa Âm Phủ', every: 3, mult: 2.2 } },
    },
    {
      id: 'mountain', name: 'Núi Khổng Lồ', icon: 'mountain-cave', levels: '18–23',
      desc: 'Hang động của ogre và người khổng lồ.',
      monsters: [
        { id: 'ogre', name: 'Ogre', level: 18 },
        { id: 'black_bear', name: 'Gấu Đen', level: 19 },
        { id: 'cyclops', name: 'Cyclops', level: 21 },
        { id: 'manticore', name: 'Manticore', level: 22 },
      ],
      boss: { id: 'hill_giant', name: 'Vua Khổng Lồ', level: 24, special: { name: 'Ném Đá', every: 3, mult: 2.2 } },
    },
    {
      id: 'swamp', name: 'Đầm Lầy Rồng', icon: 'cave-entrance', levels: '24–29',
      desc: 'Vùng đầm độc nơi lũ rồng con sinh sống.',
      monsters: [
        { id: 'basilisk', name: 'Tử Xà', level: 24 },
        { id: 'wyvern', name: 'Rồng Hai Chân', level: 25 },
        { id: 'hydra5', name: 'Rắn Năm Đầu', level: 27 },
        { id: 'death_knight', name: 'Kỵ Sĩ Tử Thần', level: 28 },
      ],
      boss: { id: 'golden_dragon', name: 'Kim Long', level: 30, special: { name: 'Hơi Thở Vàng', every: 3, mult: 2.4 } },
    },
    {
      id: 'lair', name: 'Hang Hắc Long', icon: 'dragon-breath', levels: '30–35',
      desc: 'Sào huyệt của con rồng đen đã khủng bố vùng đất này nhiều năm.',
      monsters: [
        { id: 'ice_dragon', name: 'Băng Long', level: 30 },
        { id: 'storm_dragon', name: 'Lôi Long', level: 32 },
        { id: 'bone_dragon', name: 'Rồng Xương', level: 33 },
      ],
      boss: { id: 'shadow_dragon', name: 'HẮC LONG', level: 36, final: true, special: { name: 'Hắc Hỏa', every: 3, mult: 2.5 } },
    },
  ];

  // slot: weapon | armor | shield | potion
  const ITEMS = {
    // Vũ khí
    club:        { name: 'Gậy Gỗ',         slot: 'weapon', icon: 'wood-club',        atk: 3,   price: 0,     level: 1 },
    dagger:      { name: 'Dao Găm',        slot: 'weapon', icon: 'broad-dagger',     atk: 7,   price: 60,    level: 3 },
    broadsword:  { name: 'Kiếm Sắt',       slot: 'weapon', icon: 'broadsword',       atk: 13,  price: 220,   level: 7 },
    mace:        { name: 'Chùy Gai',       slot: 'weapon', icon: 'spiked-mace',      atk: 21,  price: 650,   level: 12 },
    battleaxe:   { name: 'Rìu Chiến',      slot: 'weapon', icon: 'battle-axe',       atk: 31,  price: 1600,  level: 17 },
    greatsword:  { name: 'Đại Kiếm',       slot: 'weapon', icon: 'two-handed-sword', atk: 44,  price: 3600,  level: 22 },
    waraxe:      { name: 'Rìu Song Nhận',  slot: 'weapon', icon: 'war-axe',          atk: 60,  price: 7500,  level: 27 },
    relic:       { name: 'Thánh Kiếm Diệt Long', slot: 'weapon', icon: 'relic-blade', atk: 82, price: 0,    level: 30, drop: true },

    // Giáp
    vest:        { name: 'Áo Da Mỏng',     slot: 'armor', icon: 'leather-vest',  def: 2,  price: 0,    level: 1 },
    leather:     { name: 'Giáp Da',        slot: 'armor', icon: 'leather-armor', def: 5,  price: 70,   level: 3 },
    chain:       { name: 'Giáp Xích',      slot: 'armor', icon: 'chain-mail',    def: 10, price: 260,  level: 7 },
    scale:       { name: 'Giáp Vảy',       slot: 'armor', icon: 'scale-mail',    def: 16, price: 700,  level: 12 },
    lamellar:    { name: 'Giáp Lá',        slot: 'armor', icon: 'lamellar',      def: 24, price: 1700, level: 17 },
    breastplate: { name: 'Giáp Ngực Thép', slot: 'armor', icon: 'breastplate',   def: 34, price: 3800, level: 22 },

    // Khiên
    round:       { name: 'Khiên Tròn',     slot: 'shield', icon: 'round-shield',   def: 3,  price: 90,   level: 4 },
    checked:     { name: 'Khiên Hiệp Sĩ',  slot: 'shield', icon: 'checked-shield', def: 7,  price: 450,  level: 10 },
    spiked:      { name: 'Khiên Gai',      slot: 'shield', icon: 'spiked-shield',  def: 12, price: 1500, level: 17 },
    dragonshield:{ name: 'Khiên Vảy Rồng', slot: 'shield', icon: 'dragon-shield',  def: 20, price: 0,    level: 24, drop: true },

    // Bình máu
    potion_s:    { name: 'Bình Máu Nhỏ',   slot: 'potion', icon: 'health-potion', heal: 60,  price: 15 },
    potion_m:    { name: 'Bình Máu Vừa',   slot: 'potion', icon: 'health-potion', heal: 220, price: 55 },
    potion_l:    { name: 'Bình Máu Lớn',   slot: 'potion', icon: 'magic-potion',  heal: 650, price: 150 },
  };

  // Đồ rơi đặc biệt từ trùm (lần đầu hạ)
  const BOSS_DROPS = {
    hill_giant: 'dragonshield',
    golden_dragon: 'relic',
  };

  const SHOP = ['potion_s', 'potion_m', 'potion_l',
    'dagger', 'broadsword', 'mace', 'battleaxe', 'greatsword', 'waraxe',
    'leather', 'chain', 'scale', 'lamellar', 'breastplate',
    'round', 'checked', 'spiked'];

  const DATA = { CLASSES, ZONES, ITEMS, BOSS_DROPS, SHOP };
  if (typeof module !== 'undefined' && module.exports) module.exports = DATA;
  else root.GAME_DATA = DATA;
})(typeof window !== 'undefined' ? window : globalThis);
