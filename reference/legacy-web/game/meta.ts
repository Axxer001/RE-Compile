import { levelFromXp } from '../hooks/useProgression';
import type { Player } from '../types';
import type { RunSummary } from './types';

export function xpForRun(s: RunSummary): number {
  const compiles = Object.values(s.compiled).reduce((a, b) => a + b, 0);
  return (
    Math.floor(s.durationSec / 3) +
    Math.floor(s.kills / 4) +
    15 * compiles +
    (s.won ? 150 : 0)
  );
}

export function applyRunResult(p: Player, s: RunSummary): Player {
  const first =
    !p.completedQuests.includes('awakening') && (s.compiled['awakening'] ?? 0) > 0;
  const xp = (p.xp ?? 0) + xpForRun(s) + (first ? 50 : 0);

  const c = p.career ?? {
    runs: 0,
    bestTimeSec: 0,
    totalKills: 0,
    recipesCompiled: {},
  };

  const recipesCompiled = { ...c.recipesCompiled };
  for (const [id, n] of Object.entries(s.compiled)) {
    recipesCompiled[id] = (recipesCompiled[id] ?? 0) + n;
  }

  return {
    ...p,
    xp,
    level: levelFromXp(xp),
    lastPlayed: Date.now(),
    completedQuests: first
      ? [...p.completedQuests, 'awakening']
      : p.completedQuests,
    career: {
      runs: c.runs + 1,
      bestTimeSec: Math.max(c.bestTimeSec, Math.floor(s.durationSec)),
      totalKills: c.totalKills + s.kills,
      recipesCompiled,
    },
  };
}
