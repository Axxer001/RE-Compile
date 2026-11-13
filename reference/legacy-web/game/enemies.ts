import type { Enemy } from './types';

export type EnemyType = 'glitch' | 'nullref' | 'segfault' | 'race';

export interface EnemyTypeConfig {
  type: EnemyType;
  glyph: string;
  baseHp: number;
  baseSpeed: number;
  contactDmg: number;
  bytes: number;
  radius: number;
  appearTimeSec: number;
  color: string;
}

export const ENEMY_TYPES: Record<EnemyType, EnemyTypeConfig> = {
  glitch: {
    type: 'glitch',
    glyph: '#',
    baseHp: 18,
    baseSpeed: 62,
    contactDmg: 8,
    bytes: 1,
    radius: 12,
    appearTimeSec: 0,
    color: '#ef4444', // danger red
  },
  nullref: {
    type: 'nullref',
    glyph: 'null',
    baseHp: 30,
    baseSpeed: 78,
    contactDmg: 10,
    bytes: 2,
    radius: 14,
    appearTimeSec: 60,
    color: '#60a5fa', // info blue
  },
  segfault: {
    type: 'segfault',
    glyph: 'SEGV',
    baseHp: 120,
    baseSpeed: 48,
    contactDmg: 18,
    bytes: 5,
    radius: 20,
    appearTimeSec: 180,
    color: '#c084fc', // purple
  },
  race: {
    type: 'race',
    glyph: '&&',
    baseHp: 14,
    baseSpeed: 105,
    contactDmg: 6,
    bytes: 1,
    radius: 10,
    appearTimeSec: 300,
    color: '#facc15', // warn yellow
  },
};

export function scaleEnemy(
  type: EnemyType,
  t: number,
  playerBaseSpeed: number,
  isElite = false,
  id = 0,
  x = 0,
  y = 0,
  playerLevel = 1,
  isBoss = false
): Enemy {
  const cfg = ENEMY_TYPES[type];

  // Level tier bonus (every 5 levels: +25% HP, +1x EXP bytes)
  const levelTier = Math.floor(playerLevel / 5);
  const levelHpMult = 1 + levelTier * 0.25;

  // hp = baseHp * (1 + t / 90) * levelHpMult
  let hp = Math.round(cfg.baseHp * (1 + t / 90) * levelHpMult);

  // speed = min(baseSpeed + 0.1 * t + (levelTier * 3), 0.92 * playerBaseSpeed)
  const maxAllowedSpeed = 0.92 * playerBaseSpeed;
  const rawSpeed = cfg.baseSpeed + 0.1 * t + levelTier * 3;
  const speed = Math.min(rawSpeed, maxAllowedSpeed);

  let radius = cfg.radius;
  let bytes = cfg.bytes * (1 + levelTier);
  let damage = cfg.contactDmg;
  let glyph = cfg.glyph;
  let bossTitle: string | undefined;

  if (isBoss) {
    hp = Math.round(hp * 7);
    radius = Math.round(radius * 2.2);
    damage = Math.round(damage * 1.6);
    bytes = Math.round(bytes * 10);
    glyph = `[${cfg.glyph}.DAEMON]`;
    bossTitle = `LEVEL ${playerLevel} BOSS: ${type.toUpperCase()}_DAEMON`;
  } else if (isElite) {
    hp = Math.round(hp * 3);
    radius = Math.round(radius * 1.3);
    bytes *= 3;
  }

  return {
    id,
    type,
    glyph,
    x,
    y,
    hp,
    maxHp: hp,
    speed,
    damage,
    bytes,
    radius,
    color: isBoss ? '#f43f5e' : cfg.color,
    isElite: isElite || isBoss,
    isBoss,
    bossTitle,
    hitTimer: 0,
  };
}
