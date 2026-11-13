import type { Quest } from '../types';

export const QUESTS: Record<string, Quest> = {
  awakening: {
    id: 'awakening',
    title: 'Awakening',
    chapter: 'Chapter I — First Light',
    description:
      'You have been compiled into the Codeverse. The Oracle speaks before you: ' +
      '"Speak, and the world shall hear. Utter the ancient greeting to prove you exist."',
    objective: 'Print the exact text: Hello, World',
    hint: 'Use the print statement of your chosen language.',
    xpReward: 50,
    unlocks: ['loops'],
    expectedOutput: 'Hello, World',
    starterCode: {
      wizard: `# Wizard of the Python Order\n# Speak your first words\n\n`,
      warrior: `// Warrior of the C++ Clan\n// Speak your first words\n\n#include <iostream>\nint main() {\n  \n  return 0;\n}\n`,
      rogue: `// Rogue of the JavaScript Guild\n// Speak your first words\n\n`,
      cleric: `-- Cleric of the SQL Sanctum\n-- Speak your first words\n\n`,
    },
    language: {
      wizard: 'python',
      warrior: 'cpp',
      rogue: 'javascript',
      cleric: 'sql',
    },
  },
};