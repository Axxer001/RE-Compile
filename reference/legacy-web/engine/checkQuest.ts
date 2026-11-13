import type { ExecutionResult, QuestCheck } from '../types';

export function checkQuest(
  quest: { expectedOutput: string },
  result: ExecutionResult
): QuestCheck {
  const normalize = (s: string): string =>
    s.replace(/\r\n/g, '\n').replace(/\s+$/g, '').trim();

  const got = normalize(result.stdout);
  const want = normalize(quest.expectedOutput);

  if (!result.ok) {
    return { passed: false, reason: result.stderr || 'Execution error.' };
  }
  if (got === want) {
    return { passed: true, reason: 'Objective complete.' };
  }
  if (!got) {
    return {
      passed: false,
      reason: 'No output detected. Did you print anything?',
    };
  }
  return {
    passed: false,
    reason: `Expected:\n  ${want}\n\nGot:\n  ${got}`,
  };
}