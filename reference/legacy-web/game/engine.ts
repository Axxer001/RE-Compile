import { CLASSES } from '../data/classes';
import type { ClassId, Language } from '../types';
import { deriveStats } from './classes';
import {
  CORE_CACHE_RADIUS,
  CORE_CACHE_UP,
  DESPAWN_DIST,
  IFRAMES_DURATION,
  RUN_LENGTH_SEC,
  SPATIAL_CELL_SIZE,
  STEP,
} from './constants';
import { Director } from './director';
import { InputManager } from './input';
import { readPalette, type CanvasPalette } from './palette';
import { createGem, updatePickups } from './pickups';
import { RECIPES, recipesForHero } from './recipes';
import { renderGame } from './render';
import { mulberry32, type SeededRng } from './rng';
import { rollOffer } from './offer';
import { createStartingBag, SNIPPETS } from './snippets';
import { SpatialHash } from './spatial';
import { GameStore } from './store';
import type {
  Bag,
  DamageNumber,
  EffectiveStats,
  Enemy,
  EngineOptions,
  EngineSettings,
  Gem,
  HudSnapshot,
  Phase,
  PlayerStats,
  Projectile,
  RunSummary,
  Snippet,
  SnippetId,
  UpgradeId,
  UpgradeRanks,
} from './types';
import { applyUpgrades, initialUpgradeRanks, UPGRADES } from './upgrades';
import { createWeaponState, updateWeapons, type WeaponState } from './weapons';

export class GameEngine {
  readonly classId: ClassId;
  readonly language: Language;
  readonly heroLevel: number;
  settings: EngineSettings;
  readonly onGameOverCallback?: (summary: RunSummary) => void;

  phase: Phase = 'running';
  timeSec = 0;
  kills = 0;
  level = 1;
  xp = 0;
  nextXp = 4;
  up = 0;
  upSpent = 0;

  ranks: UpgradeRanks = initialUpgradeRanks();
  bag: Bag;
  compiledCounts: Record<string, number> = {};
  buildLines: Snippet[] = [];
  currentOffer: Snippet[] = [];
  levelUpQueue = 0;

  basePlayerStats: PlayerStats;
  effectiveStats: EffectiveStats;
  weaponState: WeaponState;
  palette: CanvasPalette;
  rng: SeededRng;
  director: Director;
  spatialHash: SpatialHash<Enemy>;
  input: InputManager = new InputManager();
  store: GameStore;

  player: {
    x: number;
    y: number;
    hp: number;
    maxHp: number;
    radius: number;
    iframes: number;
  };

  enemies: Enemy[] = [];
  projectiles: Projectile[] = [];
  gems: Gem[] = [];
  damageNumbers: DamageNumber[] = [];
  notices: DamageNumber[] = []; // reward text (e.g. core cache pickups), shown even with damage numbers off
  caches: { x: number; y: number }[] = []; // core caches dropped by bosses
  orbitBlades: { x: number; y: number; radius: number; damage: number }[] = [];

  private started = false;
  private canvas: HTMLCanvasElement | null = null;
  private ctx: CanvasRenderingContext2D | null = null;
  private raf = 0;
  private lastTime = 0;
  private acc = 0;
  private nextDnId = 1;

  constructor(opts: EngineOptions, seed = Date.now()) {
    this.classId = opts.classId;
    const cls = CLASSES.find((c) => c.id === opts.classId) ?? CLASSES[0];
    this.language = cls.language;
    this.heroLevel = opts.heroLevel ?? 1;

    this.settings = {
      fireMode: opts.settings?.fireMode ?? 'auto',
      reducedMotion: opts.settings?.reducedMotion ?? false,
      damageNumbers: opts.settings?.damageNumbers ?? true,
    };
    this.onGameOverCallback = opts.onGameOver;

    this.bag = createStartingBag(this.language);
    this.basePlayerStats = deriveStats(this.classId);
    this.effectiveStats = applyUpgrades(this.basePlayerStats, this.ranks);
    this.weaponState = createWeaponState(this.classId);
    this.palette = readPalette(cls.color);

    this.rng = mulberry32(seed);
    this.director = new Director(this.rng);
    this.spatialHash = new SpatialHash<Enemy>(SPATIAL_CELL_SIZE);

    this.player = {
      x: 0,
      y: 0,
      hp: this.effectiveStats.maxHp,
      maxHp: this.effectiveStats.maxHp,
      radius: 14,
      iframes: 0,
    };

    const initialSnapshot: HudSnapshot = {
      phase: this.phase,
      hp: this.player.hp,
      maxHp: this.player.maxHp,
      level: this.level,
      xp: this.xp,
      nextXp: this.nextXp,
      timeSec: 0,
      kills: 0,
      up: this.up,
      bagCount: this.getBagItemCount(),
      readyRecipeCount: this.getReadyRecipeCount(),
      activeLanguage: this.language,
    };
    this.store = new GameStore(initialSnapshot);
  }

  start(canvas: HTMLCanvasElement): void {
    if (this.started) return;
    this.started = true;
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');

    this.input.attach(canvas, window, {
      onSpace: () => this.onSpace(),
      onEscape: () => this.onEscape(),
      onDigit: (d) => this.onDigit(d),
    });

    window.addEventListener('blur', this.onBlur);
    document.addEventListener('visibilitychange', this.onVisibility);

    this.lastTime = performance.now();
    this.raf = requestAnimationFrame(this.frame);
  }

  destroy(): void {
    if (!this.started) return;
    this.started = false;
    cancelAnimationFrame(this.raf);
    this.input.detach();
    window.removeEventListener('blur', this.onBlur);
    document.removeEventListener('visibilitychange', this.onVisibility);
  }

  /** Apply live setting changes from the UI; omitted values keep their current setting. */
  updateSettings(next: Partial<EngineSettings>): void {
    this.settings = {
      fireMode: next.fireMode ?? this.settings.fireMode,
      reducedMotion: next.reducedMotion ?? this.settings.reducedMotion,
      damageNumbers: next.damageNumbers ?? this.settings.damageNumbers,
    };
  }

  private onBlur = (): void => {
    if (this.phase === 'running') {
      this.setPhase('paused');
    }
  };

  private onVisibility = (): void => {
    if (document.hidden && this.phase === 'running') {
      this.setPhase('paused');
    }
  };

  onSpace(): void {
    if (this.phase === 'running') {
      this.setPhase('terminal');
    } else if (this.phase === 'terminal') {
      this.setPhase('running');
    }
  }

  onEscape(): void {
    if (this.phase === 'running') {
      this.setPhase('paused');
    } else if (this.phase === 'paused') {
      this.setPhase('running');
    } else if (this.phase === 'terminal') {
      this.setPhase('running');
    }
  }

  onDigit(digit: number): void {
    if (this.phase === 'levelup') {
      const index = digit - 1;
      if (this.currentOffer[index]) {
        this.pickSnippet(this.currentOffer[index].id);
      }
    }
  }

  setPhase(next: Phase): void {
    if (this.phase === next || this.phase === 'gameover') return;
    this.phase = next;
    this.updateSnapshot(true);
  }

  private frame = (now: number): void => {
    if (!this.started) return;
    this.raf = requestAnimationFrame(this.frame);

    const dt = Math.min(0.1, (now - this.lastTime) / 1000);
    this.lastTime = now;

    if (this.phase === 'running') {
      this.acc += dt;
      while (this.acc >= STEP) {
        this.step(STEP);
        this.acc -= STEP;
      }
    }

    this.render();
    this.store.flush(now);
  };

  step(dt: number): void {
    if (this.phase !== 'running') return;

    // 1. Advance run clock
    this.timeSec += dt;
    if (this.timeSec >= RUN_LENGTH_SEC) {
      this.handleGameOver(true);
      return;
    }

    // 2. Player movement
    const move = this.input.getMovement();
    this.player.x += move.dx * this.effectiveStats.moveSpeed * dt;
    this.player.y += move.dy * this.effectiveStats.moveSpeed * dt;

    // 3. Health regeneration
    if (this.effectiveStats.hpRegen > 0 && this.player.hp < this.player.maxHp) {
      this.player.hp = Math.min(this.player.maxHp, this.player.hp + this.effectiveStats.hpRegen * dt);
    }

    // 4. Invulnerability timer
    if (this.player.iframes > 0) {
      this.player.iframes -= dt;
    }

    // 5. Weapons
    const aim = this.canvas
      ? this.input.getAimVector(this.canvas.width / 2, this.canvas.height / 2)
      : { vx: 1, vy: 0, angle: 0 };
    const shouldFire = this.settings.fireMode === 'auto' || this.input.isMouseDown;

    const weaponOut = updateWeapons(
      dt,
      this.weaponState,
      {
        playerX: this.player.x,
        playerY: this.player.y,
        aimVx: aim.vx,
        aimVy: aim.vy,
        aimAngle: aim.angle,
        stats: this.effectiveStats,
        color: this.palette.accent,
      },
      shouldFire
    );
    this.projectiles.push(...weaponOut.newProjectiles);
    this.orbitBlades = weaponOut.orbitBlades;

    // 6. Spawn Director
    const viewW = this.canvas ? this.canvas.width : 800;
    const viewH = this.canvas ? this.canvas.height : 600;
    const spawnedEnemies = this.director.update(dt, this.timeSec, {
      playerX: this.player.x,
      playerY: this.player.y,
      viewportW: viewW,
      viewportH: viewH,
      liveEnemyCount: this.enemies.length,
      playerBaseSpeed: this.basePlayerStats.moveSpeed,
      playerLevel: this.level,
    });
    this.enemies.push(...spawnedEnemies);

    // 7. Spatial Hash partition for alive enemies
    this.spatialHash.clear();
    for (const enemy of this.enemies) {
      this.spatialHash.insert(enemy);
    }

    // 8. Projectile collisions
    for (const proj of this.projectiles) {
      proj.x += proj.vx * dt;
      proj.y += proj.vy * dt;
      proj.ttl -= dt;

      if (proj.ttl <= 0 || proj.hitsLeft <= 0) continue;

      const candidates = this.spatialHash.query(proj.x, proj.y, proj.radius);
      for (const enemy of candidates) {
        if (!enemy.dead && !proj.hitEnemyIds.has(enemy.id)) {
          proj.hitEnemyIds.add(enemy.id);
          enemy.hp -= proj.damage;
          enemy.hitTimer = 0.15;
          proj.hitsLeft--;

          this.spawnDamageNumber(enemy.x, enemy.y - 12, `-${proj.damage}`, this.palette.accent);

          if (enemy.hp <= 0 && !enemy.dead) this.killEnemy(enemy, this.palette.info);

          if (proj.hitsLeft <= 0) break;
        }
      }
    }

    // 9. Shockwave pulse collisions
    if (this.weaponState.activePulse) {
      const pulse = this.weaponState.activePulse;
      pulse.elapsed += dt;
      pulse.radius = pulse.maxRadius * (pulse.elapsed / pulse.duration);

      const targets = this.spatialHash.query(pulse.x, pulse.y, pulse.radius);
      for (const enemy of targets) {
        if (!enemy.dead && !pulse.hitEnemies.has(enemy.id)) {
          pulse.hitEnemies.add(enemy.id);
          enemy.hp -= pulse.damage;
          enemy.hitTimer = 0.2;

          this.spawnDamageNumber(enemy.x, enemy.y - 12, `-${pulse.damage}`, this.palette.info);

          if (enemy.hp <= 0 && !enemy.dead) this.killEnemy(enemy, this.palette.info);
        }
      }

      if (pulse.elapsed >= pulse.duration) {
        this.weaponState.activePulse = null;
      }
    }

    // 10. Orbit blade collisions
    for (const blade of this.orbitBlades) {
      const hitCandidates = this.spatialHash.query(blade.x, blade.y, blade.radius);
      for (const enemy of hitCandidates) {
        if (!enemy.dead && enemy.hitTimer <= 0) {
          enemy.hp -= blade.damage;
          enemy.hitTimer = 0.35; // cooldown between blade hits

          this.spawnDamageNumber(enemy.x, enemy.y - 12, `-${blade.damage}`, this.palette.warn);

          if (enemy.hp <= 0 && !enemy.dead) this.killEnemy(enemy, this.palette.warn);
        }
      }
    }

    // 11. Enemy movement & Player contact
    let playerHitDamage = 0;
    for (const enemy of this.enemies) {
      if (enemy.dead) continue;

      if (enemy.hitTimer > 0) enemy.hitTimer -= dt;

      const edx = this.player.x - enemy.x;
      const edy = this.player.y - enemy.y;
      const dist = Math.hypot(edx, edy);

      if (dist > 0) {
        enemy.x += (edx / dist) * enemy.speed * dt;
        enemy.y += (edy / dist) * enemy.speed * dt;
      }

      // Check contact with player
      if (dist < enemy.radius + this.player.radius) {
        playerHitDamage = Math.max(playerHitDamage, enemy.damage);
      }
    }

    if (playerHitDamage > 0 && this.player.iframes <= 0) {
      this.player.hp -= playerHitDamage;
      this.player.iframes = IFRAMES_DURATION;
      this.spawnDamageNumber(this.player.x, this.player.y - 18, `-${playerHitDamage}`, this.palette.danger);

      if (this.player.hp <= 0) {
        this.player.hp = 0;
        this.handleGameOver(false);
        return;
      }
    }

    // 12. Despawn & Recycle distant entities
    this.enemies = this.enemies.filter((e) => {
      if (e.dead) return false;
      const dist = Math.hypot(e.x - this.player.x, e.y - this.player.y);
      return dist <= DESPAWN_DIST;
    });
    this.projectiles = this.projectiles.filter((p) => p.ttl > 0 && p.hitsLeft > 0);

    // 13. Pickups & Level progression
    const pickupRes = updatePickups(
      dt,
      this.gems,
      this.player.x,
      this.player.y,
      this.effectiveStats.pickupRadius,
      this.xp,
      this.nextXp,
      this.level
    );
    this.gems = pickupRes.remainingGems;
    this.xp = pickupRes.result.newXp;
    this.nextXp = pickupRes.result.newNextXp;
    this.level = pickupRes.result.newLevel;

    if (pickupRes.result.newLevelUps > 0) {
      this.levelUpQueue += pickupRes.result.newLevelUps;
      this.triggerLevelUp();
    }

    // 13b. Core caches dropped by bosses
    if (this.caches.length > 0) {
      const reach = this.player.radius + CORE_CACHE_RADIUS;
      const remaining: { x: number; y: number }[] = [];
      for (const cache of this.caches) {
        if (Math.hypot(cache.x - this.player.x, cache.y - this.player.y) < reach) {
          this.up += CORE_CACHE_UP;
          this.spawnNotice(cache.x, cache.y - 12, `+${CORE_CACHE_UP} UP [CORE CACHE]`, this.palette.warn);
        } else {
          remaining.push(cache);
        }
      }
      this.caches = remaining;
    }

    // 14. Floating damage numbers and reward notices
    for (const dn of this.damageNumbers) {
      dn.ttl -= dt;
      dn.y -= 20 * dt;
    }
    this.damageNumbers = this.damageNumbers.filter((dn) => dn.ttl > 0);
    for (const n of this.notices) {
      n.ttl -= dt;
      n.y -= 20 * dt;
    }
    this.notices = this.notices.filter((n) => n.ttl > 0);

    // 15. Store throttled sync
    this.updateSnapshot(false);
  }

  private triggerLevelUp(): void {
    if (this.phase === 'gameover') return;
    this.currentOffer = rollOffer({
      lang: this.language,
      heroLevel: this.heroLevel,
      bag: this.bag,
      compiledCounts: this.compiledCounts,
      rng: this.rng,
    });
    this.setPhase('levelup');
  }

  pickSnippet(snippetId: SnippetId): void {
    this.bag[snippetId] = (this.bag[snippetId] ?? 0) + 1;
    this.levelUpQueue--;

    if (this.levelUpQueue > 0) {
      this.triggerLevelUp();
    } else {
      this.currentOffer = [];
      this.setPhase('running');
    }

    this.updateSnapshot(true);
  }

  // --- Terminal Build Grid APIs ---

  buildAdd(snippetId: SnippetId): boolean {
    const owned = this.bag[snippetId] ?? 0;
    const inBuild = this.buildLines.filter((l) => l.id === snippetId).length;
    if (inBuild >= owned) return false;

    const snippet = SNIPPETS[snippetId];
    if (!snippet) return false;

    this.buildLines.push(snippet);
    this.updateSnapshot(true);
    return true;
  }

  buildRemove(index: number): void {
    if (index >= 0 && index < this.buildLines.length) {
      this.buildLines.splice(index, 1);
      this.updateSnapshot(true);
    }
  }

  buildMove(fromIndex: number, toIndex: number): void {
    if (
      fromIndex < 0 ||
      fromIndex >= this.buildLines.length ||
      toIndex < 0 ||
      toIndex >= this.buildLines.length
    ) {
      return;
    }
    const [line] = this.buildLines.splice(fromIndex, 1);
    this.buildLines.splice(toIndex, 0, line);
    this.updateSnapshot(true);
  }

  buildClear(): void {
    this.buildLines = [];
    this.updateSnapshot(true);
  }

  applyCompile(recipeId: string): { ok: boolean; reason?: string } {
    const recipe = RECIPES.find((r) => r.id === recipeId);
    if (!recipe) {
      return { ok: false, reason: 'Unknown recipe' };
    }

    if (this.heroLevel < recipe.minHeroLevel) {
      return { ok: false, reason: 'Recipe is locked for current hero level' };
    }

    const currentCompiled = this.compiledCounts[recipeId] ?? 0;
    if (currentCompiled >= recipe.maxPerRun) {
      return { ok: false, reason: 'Recipe compile cap reached for this run' };
    }

    const solution = recipe.solution[this.language] ?? [];
    const buildIds = this.buildLines.map((l) => l.id);
    if (
      buildIds.length !== solution.length ||
      !solution.every((id, idx) => buildIds[idx] === id)
    ) {
      return { ok: false, reason: 'Build lines do not match recipe solution' };
    }

    // Verify all consumed lines are available in bag
    const consumedCounts: Record<SnippetId, number> = {};
    for (const line of this.buildLines) {
      consumedCounts[line.id] = (consumedCounts[line.id] ?? 0) + 1;
    }

    for (const [id, count] of Object.entries(consumedCounts)) {
      if ((this.bag[id] ?? 0) < count) {
        return { ok: false, reason: `Missing required snippet: ${id}` };
      }
    }

    // Consume from bag
    for (const [id, count] of Object.entries(consumedCounts)) {
      this.bag[id] -= count;
      if (this.bag[id] <= 0) {
        delete this.bag[id];
      }
    }

    this.buildClear();
    this.compiledCounts[recipeId] = currentCompiled + 1;
    this.up += 1;
    this.updateSnapshot(true);

    return { ok: true };
  }

  // --- UP & Patches ---

  spendUp(upgradeId: UpgradeId): boolean {
    if (this.up < 1) return false;
    const upgrade = UPGRADES[upgradeId];
    if (!upgrade) return false;

    const currentRank = this.ranks[upgradeId] ?? 0;
    if (currentRank >= upgrade.maxRank) return false;

    this.up -= 1;
    this.upSpent += 1;
    this.ranks[upgradeId] = currentRank + 1;

    this.recalculateStats();

    if (upgradeId === 'HP') {
      this.player.maxHp = this.effectiveStats.maxHp;
      this.player.hp = Math.min(this.player.maxHp, this.player.hp + 15);
    }

    this.updateSnapshot(true);
    return true;
  }

  recalculateStats(): void {
    this.effectiveStats = applyUpgrades(this.basePlayerStats, this.ranks);
  }

  // --- Helpers & UI Sync ---

  private spawnDamageNumber(x: number, y: number, text: string, color: string): void {
    if (!this.settings.damageNumbers) return;
    this.damageNumbers.push({
      id: this.nextDnId++,
      x,
      y,
      text,
      color,
      ttl: 0.6,
      maxTtl: 0.6,
    });
  }

  private spawnNotice(x: number, y: number, text: string, color: string): void {
    this.notices.push({ id: this.nextDnId++, x, y, text, color, ttl: 1.5, maxTtl: 1.5 });
  }

  /** Shared kill path: scores the kill, drops a gem, and drops a core cache if the enemy was a boss. */
  private killEnemy(enemy: Enemy, gemColor: string): void {
    enemy.dead = true;
    this.kills++;
    this.gems.push(createGem(enemy.x, enemy.y, enemy.bytes, gemColor));
    if (this.director.bossIds.has(enemy.id)) {
      this.caches.push({ x: enemy.x, y: enemy.y });
    }
  }

  private getBagItemCount(): number {
    let count = 0;
    for (const qty of Object.values(this.bag)) {
      count += qty;
    }
    return count;
  }

  private getReadyRecipeCount(): number {
    const unlocked = recipesForHero(this.heroLevel);
    let ready = 0;
    for (const r of unlocked) {
      const compiled = this.compiledCounts[r.id] ?? 0;
      if (compiled >= r.maxPerRun) continue;
      const solution = r.solution[this.language] ?? [];
      const hasAll = solution.every((id) => (this.bag[id] ?? 0) > 0);
      if (hasAll) ready++;
    }
    return ready;
  }

  private updateSnapshot(immediate: boolean): void {
    this.store.set(
      {
        phase: this.phase,
        hp: Math.max(0, Math.round(this.player.hp)),
        maxHp: this.effectiveStats.maxHp,
        level: this.level,
        xp: this.xp,
        nextXp: this.nextXp,
        timeSec: Math.floor(this.timeSec),
        kills: this.kills,
        up: this.up,
        bagCount: this.getBagItemCount(),
        readyRecipeCount: this.getReadyRecipeCount(),
        activeLanguage: this.language,
      },
      immediate
    );
  }

  private handleGameOver(won: boolean): void {
    if (this.phase === 'gameover') return;
    this.phase = 'gameover';
    this.updateSnapshot(true);

    const summary: RunSummary = {
      won,
      durationSec: Math.floor(this.timeSec),
      kills: this.kills,
      level: this.level,
      compiled: { ...this.compiledCounts },
      upSpent: this.upSpent,
    };

    this.onGameOverCallback?.(summary);
  }

  render(): void {
    if (!this.ctx || !this.canvas) return;

    renderGame(
      this.ctx,
      this.canvas.width,
      this.canvas.height,
      {
        player: this.player,
        stats: this.effectiveStats,
        weaponState: this.weaponState,
        orbitBlades: this.orbitBlades,
        enemies: this.enemies,
        projectiles: this.projectiles,
        gems: this.gems,
        damageNumbers: this.damageNumbers,
        notices: this.notices,
        caches: this.caches,
        bossIds: this.director.bossIds,
        cursor: {
          worldX: this.player.x + (this.input.mouseX - this.canvas.width / 2),
          worldY: this.player.y + (this.input.mouseY - this.canvas.height / 2),
          canvasX: this.input.mouseX,
          canvasY: this.input.mouseY,
        },
        settings: this.settings,
      },
      this.palette
    );
  }

  // --- Dev / Debug Hooks ---

  debugFreeUp(amount = 1): void {
    this.up += amount;
    this.updateSnapshot(true);
  }

  debugAutoPick(): void {
    if (this.phase === 'levelup' && this.currentOffer.length > 0) {
      this.pickSnippet(this.currentOffer[0].id);
    }
  }
}
