import { describe, expect, it, vi } from 'vitest';
import { deriveStats } from '../src/game/classes';
import { ENEMY_CAP } from '../src/game/constants';
import { Director } from '../src/game/director';
import { ENEMY_TYPES, scaleEnemy } from '../src/game/enemies';
import { GameEngine } from '../src/game/engine';
import { updatePickups, xpRequiredForLevel } from '../src/game/pickups';
import { createRng } from '../src/game/rng';
import { SpatialHash } from '../src/game/spatial';
import { GameStore } from '../src/game/store';
import type { HudSnapshot } from '../src/game/types';
import { initialUpgradeRanks } from '../src/game/upgrades';
import { createWeaponState, updateWeapons } from '../src/game/weapons';

describe('Phase 3: Engine Core', () => {
  describe('Store (useSyncExternalStore bridge)', () => {
    const initialSnapshot: HudSnapshot = {
      phase: 'running',
      hp: 100,
      maxHp: 100,
      level: 1,
      xp: 0,
      nextXp: 4,
      timeSec: 0,
      kills: 0,
      up: 0,
      bagCount: 1,
      readyRecipeCount: 0,
      activeLanguage: 'python',
    };

    it('returns the current snapshot via get()', () => {
      const store = new GameStore(initialSnapshot);
      expect(store.get()).toEqual(initialSnapshot);
    });

    it('notifies subscribers immediately when immediate=true', () => {
      const store = new GameStore(initialSnapshot);
      const listener = vi.fn();
      const unsub = store.subscribe(listener);

      store.set({ phase: 'terminal' }, true);
      expect(listener).toHaveBeenCalledTimes(1);
      expect(store.get().phase).toBe('terminal');

      unsub();
      store.set({ phase: 'running' }, true);
      expect(listener).toHaveBeenCalledTimes(1);
    });

    it('throttles notifications to <= 10 Hz when immediate=false', () => {
      const store = new GameStore(initialSnapshot);
      const listener = vi.fn();
      store.subscribe(listener);

      store.set({ timeSec: 1 });
      store.set({ timeSec: 2 });
      expect(listener).not.toHaveBeenCalled();

      // Flush before 100ms
      store.flush(50);
      expect(listener).not.toHaveBeenCalled();

      // Flush at >= 100ms
      store.flush(105);
      expect(listener).toHaveBeenCalledTimes(1);
      expect(store.get().timeSec).toBe(2);
    });
  });

  describe('Enemy Scaling & Ceilings', () => {
    it('scales HP linearly with run time', () => {
      const glitch0 = scaleEnemy('glitch', 0, 160);
      expect(glitch0.hp).toBe(18);

      const glitch90 = scaleEnemy('glitch', 90, 160);
      // hp = baseHp * (1 + 90 / 90) = 18 * 2 = 36
      expect(glitch90.hp).toBe(36);
    });

    it('never allows enemy speed to exceed 0.92 * playerBaseSpeed', () => {
      const playerSpeed = 160;
      const speedCap = 0.92 * playerSpeed; // 147.2

      // Race condition starts at baseSpeed 105; at t = 1000s, rawSpeed = 105 + 100 = 205
      const fastEnemy = scaleEnemy('race', 1000, playerSpeed);
      expect(fastEnemy.speed).toBeLessThanOrEqual(speedCap);
      expect(fastEnemy.speed).toBeCloseTo(147.2, 1);
    });

    it('scales elite enemies with 3x HP, 1.3x radius, and 3x bytes', () => {
      const normal = scaleEnemy('nullref', 0, 160, false);
      const elite = scaleEnemy('nullref', 0, 160, true);

      expect(elite.hp).toBe(normal.hp * 3);
      expect(elite.radius).toBe(Math.round(normal.radius * 1.3));
      expect(elite.bytes).toBe(normal.bytes * 3);
      expect(elite.isElite).toBe(true);
    });
  });

  describe('Spawn Director (Deterministic seeded tests)', () => {
    it('produces identical spawns with the same seed', () => {
      const dir1 = new Director(createRng(12345));
      const dir2 = new Director(createRng(12345));

      const ctx = {
        playerX: 0,
        playerY: 0,
        viewportW: 800,
        viewportH: 600,
        liveEnemyCount: 0,
        playerBaseSpeed: 160,
      };

      const spawns1 = dir1.update(1.0, 10, ctx);
      const spawns2 = dir2.update(1.0, 10, ctx);

      expect(spawns1.length).toBe(spawns2.length);
      expect(spawns1.map((e) => ({ type: e.type, x: e.x, y: e.y }))).toEqual(
        spawns2.map((e) => ({ type: e.type, x: e.x, y: e.y }))
      );
    });

    it('respects hard cap of 220 live enemies', () => {
      const dir = new Director(createRng(42));
      const ctx = {
        playerX: 0,
        playerY: 0,
        viewportW: 800,
        viewportH: 600,
        liveEnemyCount: ENEMY_CAP - 1,
        playerBaseSpeed: 160,
      };

      // When only 1 slot is left, at most 1 enemy can spawn
      const spawns = dir.update(1.0, 300, ctx);
      expect(spawns.length).toBeLessThanOrEqual(1);

      // When cap is reached, 0 enemies spawn
      const fullCtx = { ...ctx, liveEnemyCount: ENEMY_CAP };
      const zeroSpawns = dir.update(1.0, 300, fullCtx);
      expect(zeroSpawns.length).toBe(0);
    });

    it('spawns enemies on a ring beyond viewport diagonal', () => {
      const dir = new Director(createRng(99));
      const ctx = {
        playerX: 100,
        playerY: 200,
        viewportW: 800,
        viewportH: 600,
        liveEnemyCount: 0,
        playerBaseSpeed: 160,
      };

      const halfDiag = Math.hypot(800, 600) / 2; // 500
      const expectedDist = halfDiag + 80; // 580

      const spawns = dir.update(1.0, 10, ctx);
      expect(spawns.length).toBeGreaterThan(0);
      for (const e of spawns) {
        const d = Math.hypot(e.x - ctx.playerX, e.y - ctx.playerY);
        expect(d).toBeCloseTo(expectedDist, 1);
      }
    });
  });

  describe('Weapons & Progression Upgrades', () => {
    it('applies multishot bonus and spread angle to base weapon', () => {
      const state = createWeaponState('wizard');
      const baseStats = deriveStats('wizard');

      const noBonus = updateWeapons(
        0.1,
        state,
        {
          playerX: 0,
          playerY: 0,
          aimVx: 1,
          aimVy: 0,
          aimAngle: 0,
          stats: {
            ...baseStats,
            fireRateMult: 1,
            pickupRadius: 80,
            pierceBonus: 0,
            multishotBonus: 0,
            hpRegen: 0,
            orbitCount: 0,
            pulseUnlocked: false,
            pulseTimerMax: 3,
            pulseRadius: 70,
            pulseDamage: 2,
            burstUnlocked: false,
            burstTimerMax: 2,
            burstCount: 3,
          },
        },
        true
      );
      expect(noBonus.newProjectiles.length).toBe(1);

      // Reset cooldown
      state.baseCooldownTimer = 0;

      const withBonus = updateWeapons(
        0.1,
        state,
        {
          playerX: 0,
          playerY: 0,
          aimVx: 1,
          aimVy: 0,
          aimAngle: 0,
          stats: {
            ...baseStats,
            fireRateMult: 1,
            pickupRadius: 80,
            pierceBonus: 0,
            multishotBonus: 2,
            hpRegen: 0,
            orbitCount: 0,
            pulseUnlocked: false,
            pulseTimerMax: 3,
            pulseRadius: 70,
            pulseDamage: 2,
            burstUnlocked: false,
            burstTimerMax: 2,
            burstCount: 3,
          },
        },
        true
      );
      expect(withBonus.newProjectiles.length).toBe(3);
    });

    it('generates orbiting blades with rank count', () => {
      const state = createWeaponState('warrior');
      const baseStats = deriveStats('warrior');

      const out = updateWeapons(
        0.1,
        state,
        {
          playerX: 50,
          playerY: 50,
          aimVx: 1,
          aimVy: 0,
          aimAngle: 0,
          stats: {
            ...baseStats,
            fireRateMult: 1,
            pickupRadius: 80,
            pierceBonus: 0,
            multishotBonus: 0,
            hpRegen: 0,
            orbitCount: 3,
            pulseUnlocked: false,
            pulseTimerMax: 3,
            pulseRadius: 70,
            pulseDamage: 2,
            burstUnlocked: false,
            burstTimerMax: 2,
            burstCount: 3,
          },
        },
        false
      );

      expect(out.orbitBlades.length).toBe(3);
      for (const blade of out.orbitBlades) {
        const d = Math.hypot(blade.x - 50, blade.y - 50);
        expect(d).toBeCloseTo(56, 1);
      }
    });
  });

  describe('Pickups & Level XP curve', () => {
    it('uses Bit Survivors leveling thresholds: 4 for lv1, 4 + 3*L thereafter', () => {
      expect(xpRequiredForLevel(1)).toBe(4);
      expect(xpRequiredForLevel(2)).toBe(10);
      expect(xpRequiredForLevel(3)).toBe(13);
      expect(xpRequiredForLevel(4)).toBe(16);
    });

    it('attracts gems within pickup radius and collects when < 18px', () => {
      const gems = [
        { id: 1, x: 50, y: 0, value: 1, label: '1B', color: '#60a5fa' }, // dist 50 < 80: attracted
        { id: 2, x: 10, y: 0, value: 2, label: '2B', color: '#60a5fa' }, // dist 10 < 18: collected
        { id: 3, x: 200, y: 0, value: 5, label: '5B', color: '#60a5fa' }, // dist 200 > 80: idle
      ];

      const res = updatePickups(
        0.1,
        gems,
        0, // playerX
        0, // playerY
        80, // pickupRadius
        0, // currentXp
        4, // currentNextXp
        1 // currentLevel
      );

      expect(res.result.collectedGems.length).toBe(1);
      expect(res.result.collectedGems[0].id).toBe(2);
      expect(res.result.xpGained).toBe(2);
      expect(res.remainingGems.length).toBe(2);

      // Gem 1 pulled closer
      const gem1 = res.remainingGems.find((g) => g.id === 1)!;
      expect(gem1.x).toBeLessThan(50);

      // Gem 3 untouched
      const gem3 = res.remainingGems.find((g) => g.id === 3)!;
      expect(gem3.x).toBe(200);
    });
  });

  describe('GameEngine Integration & Rules Validation', () => {
    it('initializes with starter snippet for the class language', () => {
      const pyEngine = new GameEngine({ classId: 'wizard' });
      expect(pyEngine.language).toBe('python');
      expect(pyEngine.bag['py.hello']).toBe(1);

      const cppEngine = new GameEngine({ classId: 'warrior' });
      expect(cppEngine.language).toBe('cpp');
      expect(cppEngine.bag['cpp.hello']).toBe(1);
    });

    it('manages Space routing: running <-> terminal without corrupting state', () => {
      const engine = new GameEngine({ classId: 'wizard' });
      expect(engine.phase).toBe('running');

      engine.onSpace();
      expect(engine.phase).toBe('terminal');

      engine.onSpace();
      expect(engine.phase).toBe('running');
    });

    it('manages Escape routing: running <-> paused and terminal -> running', () => {
      const engine = new GameEngine({ classId: 'wizard' });
      engine.onEscape();
      expect(engine.phase).toBe('paused');

      engine.onEscape();
      expect(engine.phase).toBe('running');

      engine.onSpace();
      expect(engine.phase).toBe('terminal');
      engine.onEscape();
      expect(engine.phase).toBe('running');
    });

    it('rejects applyCompile when snippets are missing from bag', () => {
      const engine = new GameEngine({ classId: 'wizard', heroLevel: 1 });
      // awakening needs 'py.hello'
      // Try to compile sum without having 'py.x3', 'py.y5', 'py.psum'
      engine.buildAdd('py.hello');
      const res = engine.applyCompile('sum');
      expect(res.ok).toBe(false);
      expect(engine.up).toBe(0);
    });

    it('rejects applyCompile when recipe is locked for hero level', () => {
      const engine = new GameEngine({ classId: 'wizard', heroLevel: 1 });
      // loop requires heroLevel >= 2
      const res = engine.applyCompile('loop');
      expect(res.ok).toBe(false);
      expect(res.reason).toContain('locked');
    });

    it('successfully compiles when lines are owned, awarding 1 UP and consuming lines', () => {
      const engine = new GameEngine({ classId: 'wizard', heroLevel: 1 });
      expect(engine.bag['py.hello']).toBe(1);

      const added = engine.buildAdd('py.hello');
      expect(added).toBe(true);
      expect(engine.buildLines.length).toBe(1);

      const compileRes = engine.applyCompile('awakening');
      expect(compileRes.ok).toBe(true);
      expect(engine.up).toBe(1);
      expect(engine.compiledCounts['awakening']).toBe(1);
      expect(engine.bag['py.hello']).toBeUndefined(); // consumed
      expect(engine.buildLines.length).toBe(0); // cleared
    });

    it('rejects applyCompile when per-run cap is reached', () => {
      const engine = new GameEngine({ classId: 'wizard', heroLevel: 1 });
      engine.compiledCounts['awakening'] = 1; // awakening cap is 1
      engine.bag['py.hello'] = 2;
      engine.buildAdd('py.hello');

      const res = engine.applyCompile('awakening');
      expect(res.ok).toBe(false);
      expect(res.reason).toContain('cap');
    });

    it('validates spendUp: rejects at 0 UP or max rank, applies upgrades correctly', () => {
      const engine = new GameEngine({ classId: 'wizard' });
      expect(engine.up).toBe(0);

      // Rejects at 0 UP
      expect(engine.spendUp('ATK')).toBe(false);

      // Award 2 UP via debug hook
      engine.debugFreeUp(2);
      expect(engine.up).toBe(2);

      // Spend 1 on ATK
      expect(engine.spendUp('ATK')).toBe(true);
      expect(engine.up).toBe(1);
      expect(engine.ranks.ATK).toBe(1);
      expect(engine.effectiveStats.damageMult).toBeGreaterThan(engine.basePlayerStats.damageMult);

      // Spend 1 on HP: heals 15 and raises maxHp
      engine.player.hp = 50;
      expect(engine.spendUp('HP')).toBe(true);
      expect(engine.ranks.HP).toBe(1);
      expect(engine.player.maxHp).toBe(engine.basePlayerStats.maxHp + 15);
      expect(engine.player.hp).toBe(65);

      // Out of UP now
      expect(engine.spendUp('ATK')).toBe(false);
    });

    it('queues level-ups and handles snippet pick resolution', () => {
      const engine = new GameEngine({ classId: 'wizard' });
      expect(engine.phase).toBe('running');

      // Simulate gem pickup triggering level up
      engine.xp = 10;
      engine.step(0.016);

      expect(engine.phase).toBe('levelup');
      expect(engine.currentOffer.length).toBe(3);

      const pickedId = engine.currentOffer[0].id;
      engine.pickSnippet(pickedId);

      expect(engine.bag[pickedId]).toBeGreaterThanOrEqual(1);
      expect(engine.phase).toBe('running');
    });

    it('triggers gameover when player HP drops to 0', () => {
      const onGameOver = vi.fn();
      const engine = new GameEngine({ classId: 'wizard', onGameOver });

      engine.player.hp = 5;
      // Add an enemy on top of player with enough HP to survive projectile and deal contact damage
      engine.enemies.push({
        id: 999,
        type: 'glitch',
        glyph: '#',
        x: engine.player.x,
        y: engine.player.y,
        hp: 100,
        maxHp: 100,
        speed: 50,
        damage: 10,
        bytes: 1,
        radius: 12,
        color: '#ef4444',
        hitTimer: 0,
      });

      engine.step(0.016);
      expect(engine.phase).toBe('gameover');
      expect(onGameOver).toHaveBeenCalledTimes(1);
      expect(onGameOver.mock.calls[0][0].won).toBe(false);
    });

    it('soaks 500 simulation steps without errors or NaN values', () => {
      const engine = new GameEngine({ classId: 'warrior' });
      for (let i = 0; i < 500; i++) {
        engine.step(0.016);
      }

      expect(isNaN(engine.player.x)).toBe(false);
      expect(isNaN(engine.player.y)).toBe(false);
      expect(isNaN(engine.player.hp)).toBe(false);
      expect(engine.enemies.length).toBeLessThanOrEqual(ENEMY_CAP);
    });
  });
});
