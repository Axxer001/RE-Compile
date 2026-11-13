import React from 'react';
import { renderToString } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { CoachMarks } from '../src/components/game/CoachMarks';
import { HudOverlay } from '../src/components/game/HudOverlay';
import { RunSummary } from '../src/components/game/RunSummary';
import { highlightCodeLine, SnippetLine } from '../src/components/game/SnippetLine';
import { SnippetPicker } from '../src/components/game/SnippetPicker';
import { DEFAULT_SETTINGS, getStoredSettings } from '../src/hooks/useSettings';
import type { HudSnapshot, RunSummary as RunSummaryType, Snippet } from '../src/game/types';
import type { Player } from '../src/types';

const DUMMY_PLAYER: Player = {
  name: 'Test',
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
  createdAt: 0,
  lastPlayed: 0,
};

function cleanHtml(html: string): string {
  return html.replace(/<!--.*?-->/g, '');
}

describe('Phase 4: React Host, HUD, and UI Overlays', () => {
  describe('useSettings & Stored Settings', () => {
    it('returns DEFAULT_SETTINGS when localStorage is empty', () => {
      expect(DEFAULT_SETTINGS).toEqual({
        fireMode: 'auto',
        reducedMotion: false,
        damageNumbers: true,
      });
      const settings = getStoredSettings();
      expect(settings.fireMode).toBe('auto');
      expect(settings.reducedMotion).toBe(false);
      expect(settings.damageNumbers).toBe(true);
    });
  });

  describe('SnippetLine & Code Highlighter', () => {
    it('tokenizes keywords, strings, and numbers into styled spans', () => {
      const tokens = highlightCodeLine('print("Hello", 42)');
      const html = renderToString(React.createElement(React.Fragment, null, tokens));

      expect(html).toContain('class="syntax-keyword"');
      expect(html).toContain('print');
      expect(html).toContain('class="syntax-string"');
      expect(html).toContain('&quot;Hello&quot;');
      expect(html).toContain('class="syntax-number"');
      expect(html).toContain('42');
    });

    it('renders SnippetLine with snippet-code class', () => {
      const html = renderToString(React.createElement(SnippetLine, { text: 'int x = 5;' }));
      expect(html).toContain('class="snippet-code "');
      expect(html).toContain('int');
      expect(html).toContain('5');
    });
  });

  describe('HudOverlay', () => {
    const baseSnapshot: HudSnapshot = {
      phase: 'running',
      hp: 85,
      maxHp: 100,
      level: 3,
      xp: 7,
      nextXp: 13,
      timeSec: 125, // 02:05
      kills: 14,
      up: 2,
      bagCount: 5,
      readyRecipeCount: 0,
      activeLanguage: 'python',
    };

    it('renders timer formatted as mm:ss and player stat values', () => {
      const html = cleanHtml(renderToString(React.createElement(HudOverlay, { snapshot: baseSnapshot })));

      expect(html).toContain('02:05');
      expect(html).toContain('85/100');
      expect(html).toContain('LV 3');
      expect(html).toContain('7/13');
      expect(html).toContain('x14');
      expect(html).toContain('UP 2');
      expect(html).toContain('5 snippets');
      expect(html).toContain('SPACE');
      expect(html).not.toContain('ready-pulse');
    });

    it('pulses terminal indicator when readyRecipeCount > 0', () => {
      const readySnapshot: HudSnapshot = {
        ...baseSnapshot,
        readyRecipeCount: 1,
      };
      const html = cleanHtml(renderToString(React.createElement(HudOverlay, { snapshot: readySnapshot })));

      expect(html).toContain('ready-pulse');
      expect(html).toContain('Terminal (1 ready!)');
    });
  });

  describe('SnippetPicker', () => {
    const mockOffers: Snippet[] = [
      { id: 'py.hello', lang: 'python', text: 'print("Hello, World")', tier: 1, unique: true },
      { id: 'py.x3', lang: 'python', text: 'x = 3', tier: 1 },
      { id: 'py.for3', lang: 'python', text: 'for i in range(3):', tier: 2 },
    ];

    it('renders 3 offers with tier chips and hotkey badges', () => {
      const onPick = vi.fn();
      const html = cleanHtml(
        renderToString(
          React.createElement(SnippetPicker, { offers: mockOffers, onPick })
        )
      );

      expect(html).toContain('LEVEL UP!');
      expect(html).toContain('TIER 1');
      expect(html).toContain('TIER 2');
      expect(html).toContain('UNIQUE');
      expect(html).toContain('print');
      expect(html).toContain('for i in range(3):');
    });
  });

  describe('RunSummary', () => {
    const defeatSummary: RunSummaryType = {
      won: false,
      durationSec: 184, // 03:04
      kills: 42,
      level: 4,
      compiled: { awakening: 1 },
      upSpent: 1,
    };

    const victorySummary: RunSummaryType = {
      won: true,
      durationSec: 600, // 10:00
      kills: 180,
      level: 14,
      compiled: { awakening: 1, sum: 1, loop: 2 },
      upSpent: 4,
    };

    it('renders defeat summary with stats and XP calculation', () => {
      const html = cleanHtml(
        renderToString(
          React.createElement(RunSummary, {
            playerBefore: DUMMY_PLAYER,
            summary: defeatSummary,
            onRetry: vi.fn(),
            onMenu: vi.fn(),
          })
        )
      );

      expect(html).toContain('CONNECTION SEVERED');
      expect(html).toContain('03:04');
      expect(html).toContain('42');
      expect(html).toContain('LV 4');
      expect(html).toContain('awakening ×1');
      expect(html).toContain('Retry Run');
      expect(html).toContain('Main Menu');
    });

    it('renders victory summary with victory styling and completion bonus', () => {
      const html = cleanHtml(
        renderToString(
          React.createElement(RunSummary, {
            playerBefore: DUMMY_PLAYER,
            summary: victorySummary,
            onRetry: vi.fn(),
            onMenu: vi.fn(),
          })
        )
      );

      expect(html).toContain('CONNECTION STABILIZED');
      expect(html).toContain('10:00');
      expect(html).toContain('180');
      expect(html).toContain('LV 14');
      expect(html).toContain('loop ×2');
    });
  });

  describe('CoachMarks', () => {
    it('renders guidance when awakening is not yet completed', () => {
      const html = renderToString(
        React.createElement(CoachMarks, { hasAwakening: false, phase: 'running' })
      );
      expect(html).toContain('WASD move');
      expect(html).toContain('SPACE');
    });

    it('renders nothing once awakening has been completed', () => {
      const html = renderToString(
        React.createElement(CoachMarks, { hasAwakening: true, phase: 'running' })
      );
      expect(html).toBe('');
    });
  });
});
