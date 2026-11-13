import { describe, expect, it, vi } from 'vitest';
import { renderToString } from 'react-dom/server';
import { createElement } from 'react';
import { BagPanel } from '../src/components/game/BagPanel';
import { PatchPanel } from '../src/components/game/PatchPanel';
import { BuildPanel } from '../src/components/game/BuildPanel';
import { SNIPPETS } from '../src/game/snippets';
import { initialUpgradeRanks, UPGRADES } from '../src/game/upgrades';
import type { Bag, Snippet } from '../src/game/types';
import type { Language } from '../src/types';

// ── Helpers ──────────────────────────────────────────────────────────────────

function cleanHtml(html: string): string {
  return html.replace(/<!--.*?-->/g, '');
}

const PY_BAG: Bag = {
  'py.hello': 1,
  'py.x3': 2,
  'py.y5': 1,
};

const BUILD_LINES: Snippet[] = [
  SNIPPETS['py.x3']!,
  SNIPPETS['py.y5']!,
];

// ── BagPanel ─────────────────────────────────────────────────────────────────

describe('Phase 5 — BagPanel', () => {
  it('renders all bag items with hotkey badges and counts', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BagPanel, {
          bag: PY_BAG,
          buildLines: [],
          onAddToBuild: vi.fn(),
        })
      )
    );

    // bag shows snippet code, not ids — check for the print keyword which is syntax-highlighted
    expect(html).toContain('print');
    // hotkeys for first 3 entries
    expect(html).toContain('>1<');
    expect(html).toContain('>2<');
    expect(html).toContain('>3<');
  });

  it('shows reduced available count when lines are in build', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BagPanel, {
          bag: PY_BAG,
          buildLines: BUILD_LINES, // uses py.x3 ×1 and py.y5 ×1
          onAddToBuild: vi.fn(),
        })
      )
    );

    // py.x3 owned=2, 1 in build → 1 available shown first
    expect(html).toContain('×1');
    // py.y5 owned=1, 1 in build → depleted class
    expect(html).toContain('depleted');
  });

  it('renders empty state when bag is empty', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BagPanel, {
          bag: {},
          buildLines: [],
          onAddToBuild: vi.fn(),
        })
      )
    );
    expect(html).toContain('level up');
  });
});

// ── PatchPanel ────────────────────────────────────────────────────────────────

describe('Phase 5 — PatchPanel', () => {
  it('renders all 11 upgrades with labels and hotkeys', () => {
    const html = cleanHtml(
      renderToString(
        createElement(PatchPanel, {
          up: 3,
          ranks: initialUpgradeRanks(),
          onSpend: vi.fn(),
        })
      )
    );

    const allIds = Object.keys(UPGRADES);
    for (const id of allIds) {
      expect(html).toContain(UPGRADES[id as keyof typeof UPGRADES].label);
    }

    // hotkeys
    expect(html).toContain('>1<');
    expect(html).toContain('>-<');
  });

  it('shows maxed ranks with MAX label', () => {
    const ranks = initialUpgradeRanks();
    ranks.ATK = 8; // ATK maxRank = 8

    const html = cleanHtml(
      renderToString(
        createElement(PatchPanel, {
          up: 5,
          ranks,
          onSpend: vi.fn(),
        })
      )
    );

    expect(html).toContain('MAX');
  });

  it('shows pip track filled proportionally', () => {
    const ranks = initialUpgradeRanks();
    ranks.CLK = 3;

    const html = cleanHtml(
      renderToString(
        createElement(PatchPanel, {
          up: 2,
          ranks,
          onSpend: vi.fn(),
        })
      )
    );

    // 3 filled pips for CLK
    const filledCount = (html.match(/patch-pip filled/g) ?? []).length;
    expect(filledCount).toBe(3);
  });
});

// ── BuildPanel ────────────────────────────────────────────────────────────────

describe('Phase 5 — BuildPanel', () => {
  const MOCK_RECIPE = {
    id: 'sum',
    title: 'Add two numbers',
    tier: 1 as const,
    minHeroLevel: 1,
    objective: 'Compute 3 + 5',
    hint: 'Add with +',
    expectedOutput: '8',
    mustContain: {},
    solution: { python: ['py.x3', 'py.y5', 'py.psum'] } as Record<Language, string[]>,
    maxPerRun: 1,
  };

  it('renders build rows with line numbers and code', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BuildPanel, {
          lang: 'python' as Language,
          recipe: MOCK_RECIPE,
          buildLines: BUILD_LINES,
          scaffoldLines: [],
          selectedIndex: null,
          onSelectLine: vi.fn(),
          onMoveLine: vi.fn(),
          onRemoveLine: vi.fn(),
          onClear: vi.fn(),
          onCompile: vi.fn(),
          isCompiling: false,
        })
      )
    );

    // Code is syntax-highlighted — the '3' is wrapped in a span, but the variable 'x' and '=' appear as plain text
    expect(html).toContain('x =');
    expect(html).toContain('y =');
    // Line numbers
    expect(html).toContain('>1<');
    expect(html).toContain('>2<');
  });

  it('shows scaffold rows for C++', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BuildPanel, {
          lang: 'cpp' as Language,
          recipe: null,
          buildLines: [],
          scaffoldLines: ['#include <iostream>', 'int main() {'],
          selectedIndex: null,
          onSelectLine: vi.fn(),
          onMoveLine: vi.fn(),
          onRemoveLine: vi.fn(),
          onClear: vi.fn(),
          onCompile: vi.fn(),
          isCompiling: false,
        })
      )
    );

    expect(html).toContain('scaffold-row');
    expect(html).toContain('#include');
  });

  it('shows empty hint when no build lines', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BuildPanel, {
          lang: 'python' as Language,
          recipe: null,
          buildLines: [],
          scaffoldLines: [],
          selectedIndex: null,
          onSelectLine: vi.fn(),
          onMoveLine: vi.fn(),
          onRemoveLine: vi.fn(),
          onClear: vi.fn(),
          onCompile: vi.fn(),
          isCompiling: false,
        })
      )
    );

    expect(html).toContain('build-empty');
  });

  it('disables compile button while compiling', () => {
    const html = cleanHtml(
      renderToString(
        createElement(BuildPanel, {
          lang: 'python' as Language,
          recipe: MOCK_RECIPE,
          buildLines: BUILD_LINES,
          scaffoldLines: [],
          selectedIndex: 0,
          onSelectLine: vi.fn(),
          onMoveLine: vi.fn(),
          onRemoveLine: vi.fn(),
          onClear: vi.fn(),
          onCompile: vi.fn(),
          isCompiling: true,
        })
      )
    );

    expect(html).toContain('Compiling');
  });
});
