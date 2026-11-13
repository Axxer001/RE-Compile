export const STEP = 1 / 60;
export const RUN_LENGTH_SEC = 600; // 10 minutes
export const ENEMY_CAP = 220;
export const IFRAMES_DURATION = 0.6; // seconds
export const DESPAWN_DIST = 1800; // px from player
export const BASE_MAGNET_RADIUS = 80; // px
export const HIT_EFFECT_DURATION = 0.5; // seconds
export const PROJECTILE_TTL = 1.4; // seconds
export const SPATIAL_CELL_SIZE = 64; // px
export const BOSS_INTERVAL_LEVELS = 10; // a boss spawns each time the hero level crosses a multiple of this
export const CORE_CACHE_UP = 3; // UP granted by a boss's core cache
export const CORE_CACHE_RADIUS = 16; // px, added to the player radius for pickup

export const PAYOUT_CAPS: Record<string, number> = {
  awakening: 1,
  sum: 1,
  loop: 2,
  branch: 2,
  accumulate: 3,
  greet: 3,
};
