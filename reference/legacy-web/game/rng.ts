// Seeded pseudo-random number generator (Mulberry32)
export interface SeededRng {
  next(): number; // [0, 1)
  range(min: number, max: number): number; // [min, max)
  rangeInt(min: number, max: number): number; // [min, max] inclusive
  pick<T>(array: readonly T[]): T;
  shuffle<T>(array: readonly T[]): T[];
}

export function createRng(seed: number): SeededRng {
  let s = seed | 0;

  function next(): number {
    s = (s + 0x6d2b79f5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  function range(min: number, max: number): number {
    return min + next() * (max - min);
  }

  function rangeInt(min: number, max: number): number {
    return Math.floor(range(min, max + 1));
  }

  function pick<T>(array: readonly T[]): T {
    if (array.length === 0) throw new Error('Cannot pick from empty array');
    const idx = Math.floor(next() * array.length);
    return array[idx];
  }

  function shuffle<T>(array: readonly T[]): T[] {
    const copy = [...array];
    for (let i = copy.length - 1; i > 0; i--) {
      const j = Math.floor(next() * (i + 1));
      const tmp = copy[i];
      copy[i] = copy[j];
      copy[j] = tmp;
    }
    return copy;
  }

  return { next, range, rangeInt, pick, shuffle };
}

export const mulberry32 = createRng;
