import { BASE_WEAPONS } from './classes';
import { PROJECTILE_TTL } from './constants';
import type { ClassId } from '../types';
import type { EffectiveStats, Projectile } from './types';

export interface WeaponState {
  classId: ClassId;
  baseCooldownTimer: number;
  orbitAngle: number;
  pulseTimer: number;
  activePulse: {
    x: number;
    y: number;
    radius: number;
    maxRadius: number;
    duration: number;
    elapsed: number;
    damage: number;
    hitEnemies: Set<number>;
  } | null;
  burstTimer: number;
  nextProjId: number;
}

export function createWeaponState(classId: ClassId): WeaponState {
  return {
    classId,
    baseCooldownTimer: 0,
    orbitAngle: 0,
    pulseTimer: 0,
    activePulse: null,
    burstTimer: 2.0, // initial delay
    nextProjId: 1,
  };
}

export interface FireBaseParams {
  playerX: number;
  playerY: number;
  aimVx: number;
  aimVy: number;
  aimAngle: number;
  stats: EffectiveStats;
  color?: string;
}

export function updateWeapons(
  dt: number,
  state: WeaponState,
  params: FireBaseParams,
  shouldFireBase: boolean
): {
  newProjectiles: Projectile[];
  orbitBlades: { x: number; y: number; radius: number; damage: number }[];
} {
  const newProjectiles: Projectile[] = [];
  const spec = BASE_WEAPONS[state.classId];

  // 1. Base weapon firing
  state.baseCooldownTimer -= dt;
  if (shouldFireBase && state.baseCooldownTimer <= 0) {
    const cooldown = spec.cooldown / params.stats.fireRateMult;
    state.baseCooldownTimer = cooldown;

    const count = spec.count + params.stats.multishotBonus;
    const baseSpread = spec.spreadRad;
    const extraSpread = params.stats.multishotBonus * 0.14; // ~8 deg per bonus
    const totalSpread = baseSpread + extraSpread;

    const damage = Math.max(1, Math.round(spec.damage * params.stats.damageMult));
    const pierce = spec.pierce + params.stats.pierceBonus;

    for (let i = 0; i < count; i++) {
      let angle = params.aimAngle;
      if (count > 1) {
        const offset = (i - (count - 1) / 2) * (totalSpread / Math.max(1, count - 1));
        angle += offset;
      }

      newProjectiles.push({
        id: state.nextProjId++,
        x: params.playerX,
        y: params.playerY,
        vx: Math.cos(angle) * spec.projSpeed,
        vy: Math.sin(angle) * spec.projSpeed,
        radius: 8,
        damage,
        pierce,
        hitsLeft: pierce + 1,
        ttl: PROJECTILE_TTL,
        label: spec.label,
        color: params.color ?? '#4ade80',
        hitEnemyIds: new Set<number>(),
      });
    }
  }

  // 2. Orbit blades (ORB)
  const orbitBlades: { x: number; y: number; radius: number; damage: number }[] = [];
  if (params.stats.orbitCount > 0) {
    state.orbitAngle += dt * 3.2; // rotating speed
    const bladeCount = params.stats.orbitCount;
    const orbitDist = 56;
    const damage = Math.max(1, Math.round(2 * params.stats.damageMult));

    for (let i = 0; i < bladeCount; i++) {
      const angle = state.orbitAngle + (i * Math.PI * 2) / bladeCount;
      orbitBlades.push({
        x: params.playerX + Math.cos(angle) * orbitDist,
        y: params.playerY + Math.sin(angle) * orbitDist,
        radius: 12,
        damage,
      });
    }
  }

  // 3. Pulse (PUL)
  if (params.stats.pulseUnlocked) {
    state.pulseTimer -= dt;
    if (state.pulseTimer <= 0) {
      state.pulseTimer = params.stats.pulseTimerMax;
      state.activePulse = {
        x: params.playerX,
        y: params.playerY,
        radius: 0,
        maxRadius: params.stats.pulseRadius,
        duration: 0.3,
        elapsed: 0,
        damage: Math.max(1, Math.round(params.stats.pulseDamage)),
        hitEnemies: new Set<number>(),
      };
    }
  }

  // 4. Radial Burst (ARR)
  if (params.stats.burstUnlocked) {
    state.burstTimer -= dt;
    if (state.burstTimer <= 0) {
      state.burstTimer = params.stats.burstTimerMax;
      const burstCount = params.stats.burstCount;
      const burstDamage = Math.max(1, Math.round(2 * params.stats.damageMult));

      for (let i = 0; i < burstCount; i++) {
        const angle = (i * Math.PI * 2) / burstCount;
        newProjectiles.push({
          id: state.nextProjId++,
          x: params.playerX,
          y: params.playerY,
          vx: Math.cos(angle) * 200,
          vy: Math.sin(angle) * 200,
          radius: 6,
          damage: burstDamage,
          pierce: 0,
          hitsLeft: 1,
          ttl: 0.8,
          label: '[]',
          color: '#60a5fa',
          hitEnemyIds: new Set<number>(),
        });
      }
    }
  }

  return {
    newProjectiles,
    orbitBlades,
  };
}
