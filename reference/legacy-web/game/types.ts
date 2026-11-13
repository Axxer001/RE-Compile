import type { ClassId, Language } from '../types';

export type Phase =
  | 'running'
  | 'terminal'
  | 'levelup'
  | 'paused'
  | 'gameover';

export type SnippetId = string;

export interface Snippet {
  id: SnippetId;
  lang: Language;
  text: string;
  tier: 1 | 2 | 3;
  unique?: boolean;
}

export type Bag = Record<SnippetId, number>;

export interface Recipe {
  id: string;
  title: string;
  tier: 1 | 2 | 3;
  minHeroLevel: number;
  chapter?: string;
  story?: string;
  objective: string;
  hint: string;
  expectedOutput: string;
  mustContain: Partial<Record<Language, RegExp[]>>;
  solution: Record<Language, SnippetId[]>;
  maxPerRun: number;
}

export type UpgradeId =
  | 'ATK'
  | 'CLK'
  | 'SPD'
  | 'HP'
  | 'MAG'
  | 'PRC'
  | 'MUL'
  | 'REG'
  | 'ORB'
  | 'PUL'
  | 'ARR';

export interface Upgrade {
  id: UpgradeId;
  label: string;
  description: string;
  effectPerRank: string;
  maxRank: number;
}

export type UpgradeRanks = Record<UpgradeId, number>;

export interface WeaponSpec {
  label: string;
  damage: number;
  cooldown: number;
  projSpeed: number;
  pierce: number;
  count: number;
  spreadRad: number;
}

export interface PlayerStats {
  maxHp: number;
  moveSpeed: number;
  damageMult: number;
}

export interface EffectiveStats extends PlayerStats {
  fireRateMult: number;
  pickupRadius: number;
  pierceBonus: number;
  multishotBonus: number;
  hpRegen: number;
  orbitCount: number;
  pulseUnlocked: boolean;
  pulseTimerMax: number;
  pulseRadius: number;
  pulseDamage: number;
  burstUnlocked: boolean;
  burstTimerMax: number;
  burstCount: number;
}

export interface Enemy {
  id: number;
  type: 'glitch' | 'nullref' | 'segfault' | 'race';
  glyph: string;
  x: number;
  y: number;
  hp: number;
  maxHp: number;
  speed: number;
  damage: number;
  bytes: number;
  radius: number;
  color: string;
  isElite?: boolean;
  isBoss?: boolean;
  bossTitle?: string;
  hitTimer: number;
  dead?: boolean;
}

export interface LootBox {
  id: number;
  x: number;
  y: number;
  upReward: number;
  radius: number;
  label: string;
  color: string;
}

export interface Projectile {
  id: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  radius: number;
  damage: number;
  pierce: number;
  hitsLeft: number;
  ttl: number;
  label: string;
  color: string;
  hitEnemyIds: Set<number>;
}

export interface Gem {
  id: number;
  x: number;
  y: number;
  label: string;
  value: number;
  color: string;
}

export interface DamageNumber {
  id: number;
  x: number;
  y: number;
  text: string;
  color: string;
  ttl: number;
  maxTtl: number;
}

export interface RunSummary {
  won: boolean;
  durationSec: number;
  kills: number;
  level: number;
  compiled: Record<string, number>;
  upSpent: number;
}

export interface HudSnapshot {
  phase: Phase;
  hp: number;
  maxHp: number;
  level: number;
  xp: number;
  nextXp: number;
  timeSec: number;
  kills: number;
  up: number;
  bagCount: number;
  readyRecipeCount: number;
  activeLanguage: Language;
}

export interface EngineSettings {
  fireMode: 'auto' | 'hold';
  reducedMotion: boolean;
  damageNumbers: boolean;
}

export interface EngineOptions {
  classId: ClassId;
  heroLevel?: number;
  settings?: Partial<EngineSettings>;
  onGameOver?: (summary: RunSummary) => void;
}
