import { CLASSES } from '../data/classes';
import type { ClassId } from '../types';
import type { PlayerStats, WeaponSpec } from './types';

export function deriveStats(classId: ClassId): PlayerStats {
  const cls = CLASSES.find((c) => c.id === classId) ?? CLASSES[0];
  const { logic, patience, speed } = cls.stats;

  return {
    maxHp: 60 + patience * 10,
    moveSpeed: 120 + speed * 8, // px/s
    damageMult: 0.8 + logic * 0.05,
  };
}

export const BASE_WEAPONS: Record<ClassId, WeaponSpec> = {
  wizard: {
    label: 'print()',
    damage: 10,
    cooldown: 0.80,
    projSpeed: 420,
    pierce: 0,
    count: 1,
    spreadRad: 0,
  },
  warrior: {
    label: 'cout',
    damage: 16,
    cooldown: 1.10,
    projSpeed: 340,
    pierce: 1,
    count: 1,
    spreadRad: 0,
  },
  rogue: {
    label: 'log()',
    damage: 7,
    cooldown: 0.60,
    projSpeed: 480,
    pierce: 0,
    count: 2,
    spreadRad: 0.07, // ~4 degrees
  },
  cleric: {
    label: 'SELECT',
    damage: 9,
    cooldown: 0.90,
    projSpeed: 400,
    pierce: 2,
    count: 1,
    spreadRad: 0,
  },
};
