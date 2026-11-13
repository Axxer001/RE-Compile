import type { Gem } from './types';

export function xpRequiredForLevel(level: number): number {
  if (level <= 1) return 4;
  return 4 + 3 * level;
}

export interface PickupUpdateResult {
  collectedGems: Gem[];
  xpGained: number;
  newLevelUps: number;
  newXp: number;
  newNextXp: number;
  newLevel: number;
}

export function updatePickups(
  dt: number,
  gems: Gem[],
  playerX: number,
  playerY: number,
  pickupRadius: number,
  currentXp: number,
  currentNextXp: number,
  currentLevel: number
): {
  remainingGems: Gem[];
  result: PickupUpdateResult;
} {
  const remainingGems: Gem[] = [];
  const collectedGems: Gem[] = [];
  let xpGained = 0;

  for (const gem of gems) {
    const dx = playerX - gem.x;
    const dy = playerY - gem.y;
    const dist = Math.hypot(dx, dy);

    if (dist < 18) {
      collectedGems.push(gem);
      xpGained += gem.value;
      continue;
    }

    if (dist < pickupRadius && dist > 0) {
      const pullSpeed = 260;
      gem.x += (dx / dist) * pullSpeed * dt;
      gem.y += (dy / dist) * pullSpeed * dt;
    }

    remainingGems.push(gem);
  }

  let xp = currentXp + xpGained;
  let level = currentLevel;
  let nextXp = currentNextXp;
  let newLevelUps = 0;

  while (xp >= nextXp) {
    xp -= nextXp;
    level++;
    nextXp = xpRequiredForLevel(level);
    newLevelUps++;
  }

  return {
    remainingGems,
    result: {
      collectedGems,
      xpGained,
      newLevelUps,
      newXp: xp,
      newNextXp: nextXp,
      newLevel: level,
    },
  };
}

let nextGemId = 1;
export function createGem(x: number, y: number, value: number, color = '#60a5fa'): Gem {
  return {
    id: nextGemId++,
    x,
    y,
    value,
    label: `${value}B`,
    color,
  };
}
