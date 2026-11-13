import type { Language } from '../types';
import { missingLines, recipesForHero } from './recipes';
import type { SeededRng } from './rng';
import { SNIPPETS, snippetsFor } from './snippets';
import type { Bag, Snippet } from './types';

export interface OfferContext {
  lang: Language;
  heroLevel: number;
  bag: Bag;
  compiledCounts: Record<string, number>;
  rng: SeededRng;
}

export function rollOffer(ctx: OfferContext): Snippet[] {
  const { lang, heroLevel, bag, compiledCounts, rng } = ctx;

  // 1. Available recipes: hero has unlocked and not capped this run
  const unlockedRecipes = recipesForHero(heroLevel).filter((r) => {
    const compiled = compiledCounts[r.id] ?? 0;
    return compiled < r.maxPerRun;
  });

  // Calculate missing lines for each candidate recipe (excluding unique snippets like starters)
  const candidatesWithMissing = unlockedRecipes.map((r) => ({
    recipe: r,
    missing: missingLines(r, lang, bag).filter((id) => !SNIPPETS[id]?.unique),
  })).filter((c) => c.missing.length > 0);

  let slotA: Snippet | null = null;

  if (candidatesWithMissing.length > 0) {
    // Find minimum number of missing lines
    let minMissing = Infinity;
    for (const c of candidatesWithMissing) {
      if (c.missing.length < minMissing) minMissing = c.missing.length;
    }

    const nearest = candidatesWithMissing.filter((c) => c.missing.length === minMissing);
    const chosenCandidate = rng.pick(nearest);
    const chosenSnippetId = rng.pick(chosenCandidate.missing);
    slotA = SNIPPETS[chosenSnippetId] ?? null;
  }

  // 2. Slots B, C: weighted random from class-language pool
  // Exclude:
  // - unique: true
  // - duplicates of already selected items
  // - snippets only used by locked recipes (hero level < minHeroLevel)
  const lockedRecipes = recipesForHero(999).filter((r) => heroLevel < r.minHeroLevel);
  const lockedSnippets = new Set<string>();
  lockedRecipes.forEach((r) => {
    (r.solution[lang] ?? []).forEach((id) => lockedSnippets.add(id));
  });

  // But if a snippet is also used by an unlocked recipe, it is not exclusively locked
  const unlockedSnippets = new Set<string>();
  recipesForHero(heroLevel).forEach((r) => {
    (r.solution[lang] ?? []).forEach((id) => unlockedSnippets.add(id));
  });

  const languageSnippets = snippetsFor(lang).filter((s) => {
    if (s.unique) return false;
    // If used by locked recipe and NOT used by any unlocked recipe, exclude
    if (lockedSnippets.has(s.id) && !unlockedSnippets.has(s.id)) return false;
    return true;
  });

  function pickWeighted(pool: Snippet[], excludeIds: Set<string>): Snippet | null {
    const available = pool.filter((s) => !excludeIds.has(s.id));
    if (available.length === 0) return null;

    // Weights: tier 1 = 60, tier 2 = 30, tier 3 = 10
    const weights = available.map((s) => (s.tier === 1 ? 60 : s.tier === 2 ? 30 : 10));
    const totalWeight = weights.reduce((a, b) => a + b, 0);

    let roll = rng.range(0, totalWeight);
    for (let i = 0; i < available.length; i++) {
      roll -= weights[i];
      if (roll <= 0) return available[i];
    }
    return available[available.length - 1];
  }

  const selectedIds = new Set<string>();
  if (slotA) selectedIds.add(slotA.id);

  const slotB = pickWeighted(languageSnippets, selectedIds);
  if (slotB) selectedIds.add(slotB.id);

  const slotC = pickWeighted(languageSnippets, selectedIds);
  if (slotC) selectedIds.add(slotC.id);

  // If slotA was null (all recipes capped or completed), pick an extra weighted snippet
  const result: Snippet[] = [];
  if (slotA) result.push(slotA);
  if (slotB) result.push(slotB);
  if (slotC) result.push(slotC);

  while (result.length < 3) {
    const extra = pickWeighted(languageSnippets, selectedIds);
    if (!extra) break;
    result.push(extra);
    selectedIds.add(extra.id);
  }

  return rng.shuffle(result);
}
