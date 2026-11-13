import { describe, expect, it } from 'vitest';
import { createElement } from 'react';
import { renderToString } from 'react-dom/server';
import { xpForRun, applyRunResult } from '../src/game/meta';
import { levelFromXp } from '../src/hooks/useProgression';
import { CareerStats } from '../src/components/game/CareerStats';
import type { RunSummary } from '../src/game/types';
import type { Player, PlayerCareer } from '../src/types';

// ── Fixtures ──────────────────────────────────────────────────────────────────

const BASE_PLAYER: Player = {
  name: 'Hero',
  class: 'Wizard',
  classId: 'wizard',
  language: 'python',
  icon: '🧙',
  level: 1,
  xp: 0,
  hp: 100,
  mana: 50,
  abilities: ['fireball'],
  inventory: [],
  achievements: [],
  completedQuests: [],
  codeDrafts: {},
  createdAt: 1000,
  lastPlayed: 1000,
};

function makeRun(overrides: Partial<RunSummary> = {}): RunSummary {
  return {
    won: false,
    durationSec: 120,
    kills: 20,
    level: 3,
    compiled: {},
    upSpent: 0,
    ...overrides,
  };
}

// ── xpForRun ─────────────────────────────────────────────────────────────────

describe('Phase 6 — xpForRun', () => {
  it('awards base XP from time + kills', () => {
    const xp = xpForRun(makeRun({ durationSec: 60, kills: 4, compiled: {} }));
    // 60/3=20  +  4/4=1  = 21
    expect(xp).toBe(21);
  });

  it('awards 15 XP per compile', () => {
    const xp = xpForRun(makeRun({
      durationSec: 0,
      kills: 0,
      compiled: { awakening: 1, sum: 2 },
    }));
    // 3 compiles × 15 = 45
    expect(xp).toBe(45);
  });

  it('awards 150 bonus XP for a win', () => {
    const lost = xpForRun(makeRun({ won: false, durationSec: 0, kills: 0, compiled: {} }));
    const won  = xpForRun(makeRun({ won: true,  durationSec: 0, kills: 0, compiled: {} }));
    expect(won - lost).toBe(150);
  });

  it('returns 0 for a minimal do-nothing run', () => {
    const xp = xpForRun(makeRun({ won: false, durationSec: 0, kills: 0, compiled: {} }));
    expect(xp).toBe(0);
  });
});

// ── applyRunResult ────────────────────────────────────────────────────────────

describe('Phase 6 — applyRunResult', () => {
  it('increments career.runs by 1', () => {
    const after = applyRunResult(BASE_PLAYER, makeRun());
    expect(after.career?.runs).toBe(1);

    const after2 = applyRunResult(after, makeRun());
    expect(after2.career?.runs).toBe(2);
  });

  it('accumulates totalKills across runs', () => {
    const r1 = applyRunResult(BASE_PLAYER, makeRun({ kills: 10 }));
    const r2 = applyRunResult(r1, makeRun({ kills: 25 }));
    expect(r2.career?.totalKills).toBe(35);
  });

  it('accumulates recipesCompiled correctly', () => {
    const r1 = applyRunResult(BASE_PLAYER, makeRun({ compiled: { awakening: 1 } }));
    const r2 = applyRunResult(r1, makeRun({ compiled: { awakening: 1, sum: 2 } }));
    expect(r2.career?.recipesCompiled.awakening).toBe(2);
    expect(r2.career?.recipesCompiled.sum).toBe(2);
  });

  it('tracks bestTimeSec as the longest survived time', () => {
    const r1 = applyRunResult(BASE_PLAYER, makeRun({ durationSec: 200 }));
    const r2 = applyRunResult(r1, makeRun({ durationSec: 350 }));
    const r3 = applyRunResult(r2, makeRun({ durationSec: 100 }));
    expect(r3.career?.bestTimeSec).toBe(350);
  });

  it('correctly awards hero XP and updates level', () => {
    // 300 XP run → should push level from 1 past threshold 50 → LV 2
    const run = makeRun({ won: true, durationSec: 0, kills: 0, compiled: {} });
    // won=true gives +150 XP
    const after = applyRunResult(BASE_PLAYER, run);
    expect(after.xp).toBe(150);
    expect(after.level).toBe(levelFromXp(150)); // LV 2 (threshold 50)
    expect(after.level).toBeGreaterThanOrEqual(2);
  });

  it('awards +50 first-awakening bonus and marks quest complete', () => {
    const run = makeRun({ compiled: { awakening: 1 }, won: false, durationSec: 0, kills: 0 });
    const after = applyRunResult(BASE_PLAYER, run);
    // 15 (compile) + 50 (first awakening) = 65
    const expected = xpForRun(run) + 50;
    expect(after.xp).toBe(expected);
    expect(after.completedQuests).toContain('awakening');
  });

  it('does NOT award awakening bonus on second compilation', () => {
    const playerWithAwakening: Player = {
      ...BASE_PLAYER,
      completedQuests: ['awakening'],
    };
    const run = makeRun({ compiled: { awakening: 1 }, won: false, durationSec: 0, kills: 0 });
    const after = applyRunResult(playerWithAwakening, run);
    // Should be exactly xpForRun (no bonus)
    expect(after.xp).toBe(xpForRun(run));
    // completedQuests unchanged (no duplicate)
    expect(after.completedQuests.filter((q) => q === 'awakening').length).toBe(1);
  });

  it('preserves lastPlayed timestamp update', () => {
    const before = Date.now();
    const after = applyRunResult(BASE_PLAYER, makeRun());
    expect(after.lastPlayed).toBeGreaterThanOrEqual(before);
  });
});

// ── CareerStats component ─────────────────────────────────────────────────────

describe('Phase 6 — CareerStats', () => {
  const CAREER: PlayerCareer = {
    runs: 5,
    bestTimeSec: 245,
    totalKills: 180,
    recipesCompiled: { awakening: 3, sum: 2 },
  };

  it('renders all four career metrics', () => {
    const html = renderToString(
      createElement(CareerStats, { career: CAREER })
    );
    expect(html).toContain('5');          // runs
    expect(html).toContain('04:05');      // 245s → 04:05
    expect(html).toContain('180');        // kills
    expect(html).toContain('5');          // total compiled (3+2)
  });

  it('shows delta badges when provided', () => {
    const raw = renderToString(
      createElement(CareerStats, {
        career: CAREER,
        delta: { kills: 12, compiled: 2 },
      })
    );
    const html = raw.replace(/<!--.*?-->/g, '');
    expect(html).toContain('+12');
    expect(html).toContain('+2');
  });

  it('omits delta badges when delta is undefined', () => {
    const html = renderToString(
      createElement(CareerStats, { career: CAREER })
    );
    expect(html).not.toContain('career-delta');
  });
});
