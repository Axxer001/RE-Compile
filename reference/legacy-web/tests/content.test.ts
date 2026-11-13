import { describe, expect, it } from 'vitest';
import { compileBuild } from '../src/game/compile';
import { applyRunResult, xpForRun } from '../src/game/meta';
import { rollOffer } from '../src/game/offer';
import { RECIPES } from '../src/game/recipes';
import { createRng } from '../src/game/rng';
import { SNIPPETS } from '../src/game/snippets';
import type { Language, Player } from '../src/types';

describe('Phase 2: Content & Pipeline', () => {
  // 1. Recipe & Solution Verification across all 4 languages
  describe('Recipes and Solutions Validation', () => {
    const languages: Language[] = ['python', 'cpp', 'javascript', 'sql'];

    for (const recipe of RECIPES) {
      for (const lang of languages) {
        it(`Recipe '${recipe.id}' passes in ${lang}`, async () => {
          const solutionIds = recipe.solution[lang];
          expect(solutionIds).toBeDefined();
          expect(solutionIds.length).toBeGreaterThan(0);

          const solutionSnippets = solutionIds.map((id) => {
            const s = SNIPPETS[id];
            if (!s) throw new Error(`Snippet not found: ${id}`);
            return s;
          });

          const res = await compileBuild(lang, solutionSnippets, recipe);
          expect(res.ok).toBe(true);
          expect(res.consumed).toEqual(solutionIds);
        });

        if (recipe.solution[lang].length > 1) {
          it(`Recipe '${recipe.id}' in ${lang} fails if a line is missing`, async () => {
            const solutionIds = recipe.solution[lang];
            const partialSnippets = solutionIds.slice(0, -1).map((id) => SNIPPETS[id]);

            const res = await compileBuild(lang, partialSnippets, recipe);
            expect(res.ok).toBe(false);
          });
        }
      }
    }
  });

  // 2. Offer Generator Verification
  describe('Offer System (rollOffer)', () => {
    it('always returns 3 distinct snippets', () => {
      const rng = createRng(12345);
      const offer = rollOffer({
        lang: 'python',
        heroLevel: 1,
        bag: { 'py.hello': 1 },
        compiledCounts: {},
        rng,
      });

      expect(offer.length).toBe(3);
      const ids = new Set(offer.map((s) => s.id));
      expect(ids.size).toBe(3);
    });

    it('never offers unique snippets on level-up', () => {
      const rng = createRng(999);
      for (let i = 0; i < 20; i++) {
        const offer = rollOffer({
          lang: 'python',
          heroLevel: 2,
          bag: {},
          compiledCounts: {},
          rng,
        });
        expect(offer.some((s) => s.unique)).toBe(false);
      }
    });

    it('slot A pity offers a missing line for nearest unlocked recipe', () => {
      const rng = createRng(42);
      // Hero level 1 has sum (needs py.x3, py.y5, py.psum)
      // Hero already has py.x3 and py.y5
      const offer = rollOffer({
        lang: 'python',
        heroLevel: 1,
        bag: { 'py.x3': 1, 'py.y5': 1 },
        compiledCounts: { awakening: 1 }, // awakening capped
        rng,
      });

      // The missing line for sum is py.psum
      expect(offer.some((s) => s.id === 'py.psum')).toBe(true);
    });
  });

  // 3. Meta & Run Result Verification
  describe('Meta (applyRunResult and xpForRun)', () => {
    it('calculates XP accurately for win and loss', () => {
      const winSummary = {
        won: true,
        durationSec: 600, // 200
        kills: 100, // 25
        level: 10,
        compiled: { awakening: 1, sum: 1 }, // 30
        upSpent: 2,
      };
      // 200 + 25 + 30 + 150 = 405
      expect(xpForRun(winSummary)).toBe(405);

      const lossSummary = {
        won: false,
        durationSec: 180, // 60
        kills: 40, // 10
        level: 3,
        compiled: { awakening: 1 }, // 15
        upSpent: 1,
      };
      // 60 + 10 + 15 = 85
      expect(xpForRun(lossSummary)).toBe(85);
    });

    it('applies run result cleanly without mutating input player', () => {
      const initialPlayer: Player = {
        name: 'Tester',
        class: 'Wizard',
        classId: 'wizard',
        language: 'python',
        icon: '🧙',
        level: 1,
        xp: 0,
        hp: 100,
        mana: 50,
        abilities: [],
        inventory: [],
        achievements: [],
        completedQuests: [],
        codeDrafts: {},
        createdAt: 1000,
        lastPlayed: 1000,
      };

      const summary = {
        won: false,
        durationSec: 120, // 40
        kills: 20, // 5
        level: 2,
        compiled: { awakening: 1 }, // 15
        upSpent: 1,
      };

      // 40 + 5 + 15 + 50 (first awakening bonus) = 110 XP
      const updated = applyRunResult(initialPlayer, summary);

      expect(initialPlayer.xp).toBe(0);
      expect(updated.xp).toBe(110);
      expect(updated.completedQuests).toContain('awakening');
      expect(updated.career?.runs).toBe(1);
      expect(updated.career?.totalKills).toBe(20);
      expect(updated.career?.bestTimeSec).toBe(120);
      expect(updated.career?.recipesCompiled['awakening']).toBe(1);
    });
  });
});
