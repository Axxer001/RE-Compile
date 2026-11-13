import type { ExecutionResult } from '../../types';
import { parseAndEvalExpr, type Scope } from './expr';
import { MAX_OUTPUT_CHARS, MAX_STEPS, StepLimitExceededError } from './limits';

interface Line {
  indent: number;
  text: string;
  origIndex: number;
}

export function runPythonLite(code: string): ExecutionResult {
  const stdoutArr: string[] = [];
  let steps = 0;

  function countStep() {
    steps++;
    if (steps > MAX_STEPS) {
      throw new StepLimitExceededError();
    }
  }

  function appendOutput(text: string) {
    stdoutArr.push(text);
    if (stdoutArr.join('\n').length > MAX_OUTPUT_CHARS) {
      throw new Error('OutputLimitExceeded: Program produced too much output.');
    }
  }

  // Pre-process lines: strip comments, record indentation
  const rawLines = code.split('\n');
  const lines: Line[] = [];

  for (let i = 0; i < rawLines.length; i++) {
    const raw = rawLines[i];
    // Remove comments
    // Careful with quotes: simple strip if '#' not inside quote
    let clean = '';
    let inQuote: string | null = null;
    for (let c = 0; c < raw.length; c++) {
      const ch = raw[c];
      if (inQuote) {
        clean += ch;
        if (ch === inQuote && raw[c - 1] !== '\\') {
          inQuote = null;
        }
      } else {
        if (ch === '"' || ch === "'") {
          inQuote = ch;
          clean += ch;
        } else if (ch === '#') {
          break; // rest is comment
        } else {
          clean += ch;
        }
      }
    }

    if (clean.trim() === '') continue; // ignore blank lines

    // Indentation: spaces (tabs treated as 4 spaces)
    const matchIndent = clean.match(/^[ ]*/);
    const indent = matchIndent ? matchIndent[0].length : 0;
    lines.push({
      indent,
      text: clean.trim(),
      origIndex: i + 1,
    });
  }

  const scope: Scope = {};

  function evalPythonExpr(expr: string): unknown {
    expr = expr.trim();
    // Support f-strings: f"Hi {name}"
    const fMatch = expr.match(/^f(["'])(.*)\1$/);
    if (fMatch) {
      const inner = fMatch[2];
      return inner.replace(/\{([^}]+)\}/g, (_, varName) => {
        const trimmed = varName.trim();
        const val = evalPythonExpr(trimmed);
        return String(val ?? '');
      });
    }

    return parseAndEvalExpr(expr, scope, 'python');
  }

  function executeBlock(startIdx: number, targetIndent: number): number {
    let i = startIdx;
    while (i < lines.length) {
      countStep();
      const line = lines[i];

      if (line.indent < targetIndent) {
        // Block ended
        return i;
      }

      if (line.indent > targetIndent) {
        throw new Error(`IndentationError: unexpected indent at line ${line.origIndex}`);
      }

      // Check for 'for ... in range(...):'
      const forMatch = line.text.match(/^for\s+([a-zA-Z_][a-zA-Z0-9_]*)\s+in\s+range\((.*)\)\s*:$/);
      if (forMatch) {
        const loopVar = forMatch[1];
        const rangeArgs = forMatch[2].split(',').map((s) => s.trim());
        let start = 0;
        let end = 0;
        let step = 1;

        if (rangeArgs.length === 1) {
          end = Number(evalPythonExpr(rangeArgs[0]));
        } else if (rangeArgs.length === 2) {
          start = Number(evalPythonExpr(rangeArgs[0]));
          end = Number(evalPythonExpr(rangeArgs[1]));
        } else if (rangeArgs.length === 3) {
          start = Number(evalPythonExpr(rangeArgs[0]));
          end = Number(evalPythonExpr(rangeArgs[1]));
          step = Number(evalPythonExpr(rangeArgs[2]));
        }

        const bodyStart = i + 1;
        if (bodyStart >= lines.length || lines[bodyStart].indent <= targetIndent) {
          throw new Error(`IndentationError: expected an indented block after 'for' statement at line ${line.origIndex}`);
        }
        const bodyIndent = lines[bodyStart].indent;

        // Find block end
        let bodyEnd = bodyStart;
        while (bodyEnd < lines.length && lines[bodyEnd].indent >= bodyIndent) {
          bodyEnd++;
        }

        for (let iter = start; step > 0 ? iter < end : iter > end; iter += step) {
          countStep();
          scope[loopVar] = iter;
          executeBlock(bodyStart, bodyIndent);
        }

        i = bodyEnd;
        continue;
      }

      // Check for if / elif / else
      const ifMatch = line.text.match(/^if\s+(.*):$/);
      if (ifMatch) {
        let conditionMet = false;
        let condExpr = ifMatch[1];
        let branchTaken = Boolean(evalPythonExpr(condExpr));

        const bodyStart = i + 1;
        if (bodyStart >= lines.length || lines[bodyStart].indent <= targetIndent) {
          throw new Error(`IndentationError: expected an indented block after 'if' statement at line ${line.origIndex}`);
        }
        const bodyIndent = lines[bodyStart].indent;

        let branchEnd = bodyStart;
        while (branchEnd < lines.length && lines[branchEnd].indent >= bodyIndent) {
          branchEnd++;
        }

        if (branchTaken) {
          conditionMet = true;
          executeBlock(bodyStart, bodyIndent);
        }

        i = branchEnd;

        // Check for chained elif / else at same targetIndent
        while (i < lines.length && lines[i].indent === targetIndent) {
          const elifMatch = lines[i].text.match(/^elif\s+(.*):$/);
          const elseMatch = lines[i].text.match(/^else\s*:$/);

          if (elifMatch) {
            const nextBodyStart = i + 1;
            if (nextBodyStart >= lines.length || lines[nextBodyStart].indent <= targetIndent) {
              throw new Error(`IndentationError: expected an indented block after 'elif' at line ${lines[i].origIndex}`);
            }
            const nextBodyIndent = lines[nextBodyStart].indent;
            let nextBranchEnd = nextBodyStart;
            while (nextBranchEnd < lines.length && lines[nextBranchEnd].indent >= nextBodyIndent) {
              nextBranchEnd++;
            }

            if (!conditionMet && Boolean(evalPythonExpr(elifMatch[1]))) {
              conditionMet = true;
              executeBlock(nextBodyStart, nextBodyIndent);
            }
            i = nextBranchEnd;
            continue;
          }

          if (elseMatch) {
            const nextBodyStart = i + 1;
            if (nextBodyStart >= lines.length || lines[nextBodyStart].indent <= targetIndent) {
              throw new Error(`IndentationError: expected an indented block after 'else' at line ${lines[i].origIndex}`);
            }
            const nextBodyIndent = lines[nextBodyStart].indent;
            let nextBranchEnd = nextBodyStart;
            while (nextBranchEnd < lines.length && lines[nextBranchEnd].indent >= nextBodyIndent) {
              nextBranchEnd++;
            }

            if (!conditionMet) {
              conditionMet = true;
              executeBlock(nextBodyStart, nextBodyIndent);
            }
            i = nextBranchEnd;
            break; // after else, branch chain finishes
          }

          break; // Neither elif nor else
        }

        continue;
      }

      // Check for print(...)
      const printMatch = line.text.match(/^print\s*\((.*)\)$/s);
      if (printMatch) {
        const inner = printMatch[1].trim();
        if (!inner) {
          appendOutput('');
        } else {
          // Parse arguments if comma separated (at top level)
          // Simple arg split respecting quotes
          const args: string[] = [];
          let cur = '';
          let inQ: string | null = null;
          let parenDepth = 0;
          for (let c = 0; c < inner.length; c++) {
            const ch = inner[c];
            if (inQ) {
              cur += ch;
              if (ch === inQ && inner[c - 1] !== '\\') inQ = null;
            } else if (ch === '"' || ch === "'") {
              inQ = ch;
              cur += ch;
            } else if (ch === '(' || ch === '[' || ch === '{') {
              parenDepth++;
              cur += ch;
            } else if (ch === ')' || ch === ']' || ch === '}') {
              parenDepth--;
              cur += ch;
            } else if (ch === ',' && parenDepth === 0) {
              args.push(cur.trim());
              cur = '';
            } else {
              cur += ch;
            }
          }
          if (cur.trim()) args.push(cur.trim());

          const vals = args.map((arg) => {
            const val = evalPythonExpr(arg);
            return typeof val === 'boolean' ? (val ? 'True' : 'False') : String(val ?? 'None');
          });
          appendOutput(vals.join(' '));
        }
        i++;
        continue;
      }

      // Check for assignment: var = expr, var += expr, -=, *=
      const assignMatch = line.text.match(/^([a-zA-Z_][a-zA-Z0-9_]*)\s*(\+=|-=|\*=|=)\s*(.*)$/);
      if (assignMatch) {
        const varName = assignMatch[1];
        const op = assignMatch[2];
        const rightExpr = assignMatch[3];
        const rightVal = evalPythonExpr(rightExpr);

        if (op === '=') {
          scope[varName] = rightVal;
        } else if (op === '+=') {
          const cur = scope[varName];
          if (cur === undefined) throw new Error(`NameError: name '${varName}' is not defined`);
          if (typeof cur === 'string' || typeof rightVal === 'string') {
            scope[varName] = `${cur}${rightVal}`;
          } else {
            scope[varName] = (cur as number) + (rightVal as number);
          }
        } else if (op === '-=') {
          const cur = scope[varName];
          if (cur === undefined) throw new Error(`NameError: name '${varName}' is not defined`);
          scope[varName] = (cur as number) - (rightVal as number);
        } else if (op === '*=') {
          const cur = scope[varName];
          if (cur === undefined) throw new Error(`NameError: name '${varName}' is not defined`);
          scope[varName] = (cur as number) * (rightVal as number);
        }

        i++;
        continue;
      }

      // Unsupported syntax
      throw new Error(`SyntaxError: unsupported syntax at line ${line.origIndex}: '${line.text}'`);
    }

    return i;
  }

  try {
    executeBlock(0, 0);
    return {
      stdout: stdoutArr.join('\n'),
      stderr: '',
      ok: true,
    };
  } catch (err) {
    return {
      stdout: stdoutArr.join('\n'),
      stderr: err instanceof Error ? err.message : String(err),
      ok: false,
    };
  }
}
