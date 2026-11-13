import type { Language } from '../types';
import type { Bag, Recipe, SnippetId } from './types';

export const RECIPES: Recipe[] = [
  {
    id: 'awakening',
    title: 'Hello, World',
    tier: 1,
    minHeroLevel: 1,
    chapter: 'Chapter I — First Light',
    story: 'Your core initializes in the dark. The terminal awaits a signal that you are alive.',
    objective: 'Emit the initial boot sequence signal: Hello, World.',
    hint: 'Use the output or print function to emit the greeting string.',
    expectedOutput: 'Hello, World',
    mustContain: {
      python: [/print\s*\(/],
      cpp: [/cout\s*<</],
      javascript: [/console\.log\s*\(/],
      sql: [/SELECT/i],
    },
    solution: {
      python: ['py.hello'],
      cpp: ['cpp.hello'],
      javascript: ['js.hello'],
      sql: ['sql.hello'],
    },
    maxPerRun: 1,
  },
  {
    id: 'sum',
    title: 'Add two numbers',
    tier: 1,
    minHeroLevel: 1,
    objective: 'Compute and output the sum of 3 and 5.',
    hint: 'Add the two integer values or variables together with + and print.',
    expectedOutput: '8',
    mustContain: {
      python: [/\+/],
      cpp: [/\+/],
      javascript: [/\+/],
      sql: [/\+/],
    },
    solution: {
      python: ['py.x3', 'py.y5', 'py.psum'],
      cpp: ['cpp.x3', 'cpp.y5', 'cpp.psum'],
      javascript: ['js.x3', 'js.y5', 'js.psum'],
      sql: ['sql.sum'],
    },
    maxPerRun: 1,
  },
  {
    id: 'loop',
    title: 'Count to three',
    tier: 2,
    minHeroLevel: 2,
    objective: 'Emit numbers 0, 1, 2 on consecutive lines.',
    hint: 'Execute a loop over 3 iterations or union rows.',
    expectedOutput: '0\n1\n2',
    mustContain: {
      python: [/\bfor\b/],
      cpp: [/\bfor\b/],
      javascript: [/\bfor\b/],
      sql: [/UNION\s+ALL/i],
    },
    solution: {
      python: ['py.for3', 'py.pi'],
      cpp: ['cpp.for3', 'cpp.pi', 'cpp.close'],
      javascript: ['js.for3', 'js.pi', 'js.close'],
      sql: ['sql.u0', 'sql.u1', 'sql.u2'],
    },
    maxPerRun: 2,
  },
  {
    id: 'branch',
    title: 'Choose a path',
    tier: 2,
    minHeroLevel: 2,
    objective: 'Test if 5 > 2 and output "big".',
    hint: 'Use conditional logic (if/else or CASE WHEN) to branch execution.',
    expectedOutput: 'big',
    mustContain: {
      python: [/\bif\b/],
      cpp: [/\bif\b/],
      javascript: [/\bif\b/],
      sql: [/CASE\b/i],
    },
    solution: {
      python: ['py.x5', 'py.if', 'py.pbig', 'py.else', 'py.psmall'],
      cpp: ['cpp.x5', 'cpp.if', 'cpp.pbig', 'cpp.else', 'cpp.psmall', 'cpp.close'],
      javascript: ['js.x5', 'js.if', 'js.pbig', 'js.else', 'js.psmall', 'js.close'],
      sql: ['sql.case', 'sql.then', 'sql.else', 'sql.end'],
    },
    maxPerRun: 2,
  },
  {
    id: 'accumulate',
    title: 'Sum 0..3',
    tier: 3,
    minHeroLevel: 3,
    objective: 'Accumulate the integers 0 through 3 to yield 6.',
    hint: 'Initialize an accumulator and sum values in a loop or aggregate with SUM.',
    expectedOutput: '6',
    mustContain: {
      python: [/\+=/],
      cpp: [/\+=/],
      javascript: [/\+=/],
      sql: [/SUM\s*\(/i],
    },
    solution: {
      python: ['py.t0', 'py.for4', 'py.acc', 'py.ptot'],
      cpp: ['cpp.t0', 'cpp.for4', 'cpp.acc', 'cpp.close', 'cpp.ptot'],
      javascript: ['js.t0', 'js.for4', 'js.acc', 'js.close', 'js.ptot'],
      sql: ['sql.from', 'sql.s0', 'sql.s1', 'sql.s2', 'sql.s3', 'sql.from_end'],
    },
    maxPerRun: 3,
  },
  {
    id: 'greet',
    title: 'Greet by name',
    tier: 3,
    minHeroLevel: 3,
    objective: 'Greet Ada by name: Hi Ada.',
    hint: 'Interpolate or concatenate the name variable with "Hi ".',
    expectedOutput: 'Hi Ada',
    mustContain: {
      python: [/f["']/],
      cpp: [/<<\s*name/],
      javascript: [/`Hi\s+\$\{name\}`/],
      sql: [/\|\|/],
    },
    solution: {
      python: ['py.name', 'py.greet'],
      cpp: ['cpp.name', 'cpp.greet'],
      javascript: ['js.name', 'js.greet'],
      sql: ['sql.concat_hi', 'sql.concat_ada'],
    },
    maxPerRun: 3,
  },
];

export function recipesForHero(heroLevel: number): Recipe[] {
  return RECIPES.filter((r) => heroLevel >= r.minHeroLevel);
}

export function missingLines(recipe: Recipe, lang: Language, bag: Bag): SnippetId[] {
  const needed = recipe.solution[lang] ?? [];
  const tempBag = { ...bag };
  const missing: SnippetId[] = [];

  for (const id of needed) {
    if ((tempBag[id] ?? 0) > 0) {
      tempBag[id]--;
    } else {
      missing.push(id);
    }
  }

  return missing;
}
