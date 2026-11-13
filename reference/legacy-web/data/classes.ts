import type { CharacterClass } from '../types';

export const CLASSES: CharacterClass[] = [
  {
    id: 'wizard',
    name: 'Wizard',
    title: 'of the Python Order',
    language: 'python',
    icon: '🧙',
    color: '#7c3aed',
    description:
      'Masters of arcane logic. Wield dynamic typing and powerful libraries.',
    perks: ['Readable syntax', 'Fast prototyping', 'AI/ML affinity'],
    stats: { logic: 8, patience: 6, speed: 5 },
    startingAbility: 'print("Hello, World")',
  },
  {
    id: 'warrior',
    name: 'Warrior',
    title: 'of the C++ Clan',
    language: 'cpp',
    icon: '⚔️',
    color: '#dc2626',
    description:
      'Frontline fighters who manage memory and speed. Heavy but unstoppable.',
    perks: ['Raw performance', 'Deep control', 'Systems mastery'],
    stats: { logic: 7, patience: 4, speed: 8 },
    startingAbility: 'std::cout << "Hello, World";',
  },
  {
    id: 'rogue',
    name: 'Rogue',
    title: 'of the JavaScript Guild',
    language: 'javascript',
    icon: '🗡️',
    color: '#eab308',
    description:
      'Agile tricksters of the web. Strike fast across browser and server.',
    perks: ['Universal runtime', 'Async mastery', 'Rich ecosystem'],
    stats: { logic: 6, patience: 5, speed: 9 },
    startingAbility: 'console.log("Hello, World");',
  },
  {
    id: 'cleric',
    name: 'Cleric',
    title: 'of the SQL Sanctum',
    language: 'sql',
    icon: '✨',
    color: '#06b6d4',
    description:
      'Keepers of data. Heal broken queries and divine hidden insights.',
    perks: ['Data intuition', 'Set-based thinking', 'Relational power'],
    stats: { logic: 9, patience: 7, speed: 4 },
    startingAbility: 'SELECT "Hello, World";',
  },
];