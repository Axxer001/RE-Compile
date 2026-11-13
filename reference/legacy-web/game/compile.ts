import { checkQuest } from '../engine/checkQuest';
import { runCode } from '../engine/runCode';
import type { Language } from '../types';
import type { Recipe, Snippet, SnippetId } from './types';

export interface CompileResult {
  ok: boolean;
  stdout: string;
  stderr: string;
  reasons: string[];
  consumed: SnippetId[];
}

export function scaffold(lang: Language, codeLines: string[]): string {
  if (lang === 'cpp') {
    return [
      '#include <iostream>',
      '#include <string>',
      'using namespace std;',
      'int main() {',
      ...codeLines.map((line) => `  ${line}`),
      '  return 0;',
      '}',
    ].join('\n');
  }

  return codeLines.join('\n');
}

export async function compileBuild(
  lang: Language,
  lines: Snippet[],
  recipe: Recipe
): Promise<CompileResult> {
  const code = scaffold(lang, lines.map((l) => l.text));
  const run = await runCode(code, lang);
  const out = checkQuest(recipe, run);

  const fullText = lines.map((l) => l.text).join('\n');
  const needed = (recipe.mustContain[lang] ?? []).filter((re) => !re.test(fullText));

  const ok = run.ok && out.passed && needed.length === 0;

  const reasons: string[] = [];
  if (ok) {
    reasons.push('Build successful.');
  } else {
    if (!run.ok) {
      reasons.push(run.stderr || 'Execution failed.');
    }
    if (!out.passed && run.ok) {
      reasons.push(out.reason);
    }
    if (needed.length > 0) {
      needed.forEach((re) => reasons.push(`Missing required language construct: ${re}`));
    }
  }

  return {
    ok,
    stdout: run.stdout,
    stderr: run.stderr,
    reasons,
    consumed: ok ? lines.map((l) => l.id) : [],
  };
}
