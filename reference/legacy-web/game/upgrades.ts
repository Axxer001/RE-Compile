import type { EffectiveStats, PlayerStats, Upgrade, UpgradeId, UpgradeRanks } from './types';

export const UPGRADES: Record<UpgradeId, Upgrade> = {
  ATK: {
    id: 'ATK',
    label: 'damage++',
    description: 'Increases projectile damage multiplier.',
    effectPerRank: '+12% damage',
    maxRank: 8,
  },
  CLK: {
    id: 'CLK',
    label: 'clock_speed',
    description: 'Overclocks weapon fire rate.',
    effectPerRank: '+10% fire rate',
    maxRank: 8,
  },
  SPD: {
    id: 'SPD',
    label: 'velocity',
    description: 'Increases movement speed.',
    effectPerRank: '+6% move speed',
    maxRank: 6,
  },
  HP: {
    id: 'HP',
    label: 'heap',
    description: 'Expands heap space (maximum HP) and immediately restores 15 HP.',
    effectPerRank: '+15 max HP & heal 15',
    maxRank: 8,
  },
  MAG: {
    id: 'MAG',
    label: 'gc_radius',
    description: 'Expands garbage collection magnet radius for bytes.',
    effectPerRank: '+20% pickup radius',
    maxRank: 5,
  },
  PRC: {
    id: 'PRC',
    label: 'pierce',
    description: 'Projectiles pierce through additional enemies before vanishing.',
    effectPerRank: '+1 pierce',
    maxRank: 3,
  },
  MUL: {
    id: 'MUL',
    label: 'multishot',
    description: 'Fires additional projectiles with an 8 degree spread.',
    effectPerRank: '+1 projectile',
    maxRank: 3,
  },
  REG: {
    id: 'REG',
    label: 'regen',
    description: 'Background thread steadily repairs damaged health.',
    effectPerRank: '+0.4 HP/s',
    maxRank: 4,
  },
  ORB: {
    id: 'ORB',
    label: 'for_loop',
    description: 'Orbiting code construct blades that damage touching enemies.',
    effectPerRank: '1 blade (r=56px, 2 dmg) +1 blade/rank',
    maxRank: 5,
  },
  PUL: {
    id: 'PUL',
    label: 'if_pulse',
    description: 'Periodic conditional shockwave clearing surrounding bugs.',
    effectPerRank: 'Radial shockwave, damage and radius scale with rank',
    maxRank: 5,
  },
  ARR: {
    id: 'ARR',
    label: 'list_burst',
    description: 'Radial burst of bolts fired in all directions.',
    effectPerRank: '3+rank bolts every 3-0.25r seconds',
    maxRank: 5,
  },
};

export const UPGRADE_ORDER: UpgradeId[] = [
  'ATK',
  'CLK',
  'SPD',
  'HP',
  'MAG',
  'PRC',
  'MUL',
  'REG',
  'ORB',
  'PUL',
  'ARR',
];

export function initialUpgradeRanks(): UpgradeRanks {
  return {
    ATK: 0,
    CLK: 0,
    SPD: 0,
    HP: 0,
    MAG: 0,
    PRC: 0,
    MUL: 0,
    REG: 0,
    ORB: 0,
    PUL: 0,
    ARR: 0,
  };
}

export function applyUpgrades(base: PlayerStats, ranks: UpgradeRanks): EffectiveStats {
  const atk = ranks.ATK ?? 0;
  const clk = ranks.CLK ?? 0;
  const spd = ranks.SPD ?? 0;
  const hp = ranks.HP ?? 0;
  const mag = ranks.MAG ?? 0;
  const prc = ranks.PRC ?? 0;
  const mul = ranks.MUL ?? 0;
  const reg = ranks.REG ?? 0;
  const orb = ranks.ORB ?? 0;
  const pul = ranks.PUL ?? 0;
  const arr = ranks.ARR ?? 0;

  return {
    maxHp: base.maxHp + hp * 15,
    moveSpeed: base.moveSpeed * (1 + 0.06 * spd),
    damageMult: base.damageMult * (1 + 0.12 * atk),
    fireRateMult: 1 + 0.1 * clk,
    pickupRadius: 80 * (1 + 0.2 * mag),
    pierceBonus: prc,
    multishotBonus: mul,
    hpRegen: reg * 0.4,
    orbitCount: orb,
    pulseUnlocked: pul > 0,
    pulseTimerMax: Math.max(1.6, 4.2 - 0.4 * pul),
    pulseRadius: 70 + 14 * pul,
    pulseDamage: (2 + pul) * base.damageMult,
    burstUnlocked: arr > 0,
    burstTimerMax: Math.max(1.4, 3.0 - 0.25 * arr),
    burstCount: 3 + arr,
  };
}
