import { BOSS_INTERVAL_LEVELS, ENEMY_CAP } from './constants';
import { ENEMY_TYPES, type EnemyType, scaleEnemy } from './enemies';
import type { SeededRng } from './rng';
import type { Enemy } from './types';

export interface DirectorContext {
  playerX: number;
  playerY: number;
  viewportW: number;
  viewportH: number;
  liveEnemyCount: number;
  playerBaseSpeed: number;
  playerLevel?: number;
}

export class Director {
  private rng: SeededRng;
  private spawnTimer = 0;
  private nextEliteTime = 90;
  private nextEnemyId = 1;
  private lastSpawnedBossLevel = 0;
  /** Ids of spawned bosses, so the engine and renderer can tell them apart. */
  readonly bossIds = new Set<number>();

  constructor(rng: SeededRng) {
    this.rng = rng;
  }

  getTickInterval(t: number): number {
    return Math.max(0.16, 0.9 - t / 150);
  }

  getSpawnCount(t: number): number {
    return 1 + Math.floor(t / 120);
  }

  getUnlockedTypes(t: number): EnemyType[] {
    const types: EnemyType[] = [];
    if (t >= ENEMY_TYPES.glitch.appearTimeSec) types.push('glitch');
    if (t >= ENEMY_TYPES.nullref.appearTimeSec) types.push('nullref');
    if (t >= ENEMY_TYPES.segfault.appearTimeSec) types.push('segfault');
    if (t >= ENEMY_TYPES.race.appearTimeSec) types.push('race');
    return types;
  }

  pickType(unlocked: EnemyType[]): EnemyType {
    if (unlocked.length === 1) return unlocked[0];

    const weights: Record<EnemyType, number> = {
      glitch: 1,
      nullref: 2,
      segfault: 3,
      race: 4,
    };

    let totalWeight = 0;
    for (const type of unlocked) {
      totalWeight += weights[type] ?? 1;
    }

    let roll = this.rng.next() * totalWeight;
    for (const type of unlocked) {
      const w = weights[type] ?? 1;
      if (roll <= w) {
        return type;
      }
      roll -= w;
    }

    return unlocked[unlocked.length - 1];
  }

  update(dt: number, t: number, ctx: DirectorContext): Enemy[] {
    const pLevel = ctx.playerLevel ?? 1;
    const spawned: Enemy[] = [];

    // Boss check: one boss each time the hero level crosses a multiple of BOSS_INTERVAL_LEVELS
    if (
      pLevel >= BOSS_INTERVAL_LEVELS &&
      Math.floor(pLevel / BOSS_INTERVAL_LEVELS) > Math.floor(this.lastSpawnedBossLevel / BOSS_INTERVAL_LEVELS)
    ) {
      this.lastSpawnedBossLevel = pLevel;
      const unlocked = this.getUnlockedTypes(t);
      const bossType = unlocked[unlocked.length - 1]; // Pick strongest currently unlocked type
      const angle = this.rng.range(0, Math.PI * 2);
      const bossDist = 480;
      const bossId = this.nextEnemyId++;
      this.bossIds.add(bossId);
      spawned.push(
        scaleEnemy(
          bossType,
          t,
          ctx.playerBaseSpeed,
          true,
          bossId,
          ctx.playerX + Math.cos(angle) * bossDist,
          ctx.playerY + Math.sin(angle) * bossDist,
          pLevel,
          true
        )
      );
    }

    this.spawnTimer -= dt;
    const interval = this.getTickInterval(t);

    if (this.spawnTimer > 0) {
      return spawned;
    }

    this.spawnTimer = interval;

    const availableSlots = ENEMY_CAP - (ctx.liveEnemyCount + spawned.length);
    if (availableSlots <= 0) {
      return spawned;
    }

    const countToSpawn = Math.min(this.getSpawnCount(t), availableSlots);
    const unlocked = this.getUnlockedTypes(t);

    // Guaranteed visible perimeter ring:
    // Clamp to at least 420px away and at most 680px away so they spawn right offscreen
    const halfDiag = Math.hypot(ctx.viewportW || 800, ctx.viewportH || 600) / 2;
    const spawnRadius = Math.max(440, Math.min(680, halfDiag + 40));

    let isEliteDue = false;
    if (t >= this.nextEliteTime) {
      isEliteDue = true;
      this.nextEliteTime += 90;
    }

    for (let i = 0; i < countToSpawn; i++) {
      if (ctx.liveEnemyCount + spawned.length >= ENEMY_CAP) break;

      const type = this.pickType(unlocked);
      const isElite = isEliteDue && i === 0;
      if (isElite) isEliteDue = false;

      if (type === 'race') {
        const packSize = Math.min(6, ENEMY_CAP - (ctx.liveEnemyCount + spawned.length));
        const baseAngle = this.rng.range(0, Math.PI * 2);
        for (let p = 0; p < packSize; p++) {
          const angle = baseAngle + (p * (Math.PI * 2 / 6));
          const ex = ctx.playerX + Math.cos(angle) * spawnRadius;
          const ey = ctx.playerY + Math.sin(angle) * spawnRadius;
          spawned.push(
            scaleEnemy(
              'race',
              t,
              ctx.playerBaseSpeed,
              isElite && p === 0,
              this.nextEnemyId++,
              ex,
              ey,
              pLevel,
              false
            )
          );
        }
      } else {
        const angle = this.rng.range(0, Math.PI * 2);
        const ex = ctx.playerX + Math.cos(angle) * spawnRadius;
        const ey = ctx.playerY + Math.sin(angle) * spawnRadius;
        spawned.push(
          scaleEnemy(
            type,
            t,
            ctx.playerBaseSpeed,
            isElite,
            this.nextEnemyId++,
            ex,
            ey,
            pLevel,
            false
          )
        );
      }
    }

    return spawned;
  }
}
