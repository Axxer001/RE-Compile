import type { ExecutionResult } from '../../types';
import { parseAndEvalExpr, type Scope } from './expr';
import { MAX_OUTPUT_CHARS, MAX_STEPS, StepLimitExceededError } from './limits';

// C++ Tokenizer for statement-level and block-level parsing
type CppTokenType = 'ident' | 'number' | 'string' | 'op' | 'punct';

interface CppToken {
  type: CppTokenType;
  value: string;
  line: number;
}

function tokenizeCpp(code: string): CppToken[] {
  const tokens: CppToken[] = [];
  let i = 0;
  let line = 1;
  const n = code.length;

  while (i < n) {
    const ch = code[i];
    if (ch === '\n') {
      line++;
      i++;
      continue;
    }
    if (/\s/.test(ch)) {
      i++;
      continue;
    }

    // Skip preprocessor lines: #include, etc.
    if (ch === '#') {
      while (i < n && code[i] !== '\n') i++;
      continue;
    }

    // Skip // comments
    if (ch === '/' && code[i + 1] === '/') {
      i += 2;
      while (i < n && code[i] !== '\n') i++;
      continue;
    }

    // Skip /* */ comments
    if (ch === '/' && code[i + 1] === '*') {
      i += 2;
      while (i < n && !(code[i] === '*' && code[i + 1] === '/')) {
        if (code[i] === '\n') line++;
        i++;
      }
      i += 2;
      continue;
    }

    // Strings
    if (ch === '"') {
      let val = '';
      i++;
      while (i < n && code[i] !== '"') {
        if (code[i] === '\\' && i + 1 < n) {
          i++;
          const esc = code[i];
          if (esc === 'n') val += '\n';
          else if (esc === 't') val += '\t';
          else val += esc;
        } else {
          if (code[i] === '\n') line++;
          val += code[i];
        }
        i++;
      }
      if (i >= n) throw new Error("ParseError: unterminated string literal");
      i++; // skip "
      tokens.push({ type: 'string', value: val, line });
      continue;
    }

    // Numbers
    if (/[0-9]/.test(ch)) {
      let val = '';
      while (i < n && /[0-9.]/.test(code[i])) {
        val += code[i];
        i++;
      }
      tokens.push({ type: 'number', value: val, line });
      continue;
    }

    // Identifiers
    if (/[a-zA-Z_]/.test(ch)) {
      let val = '';
      while (i < n && /[a-zA-Z0-9_]/.test(code[i])) {
        val += code[i];
        i++;
      }
      tokens.push({ type: 'ident', value: val, line });
      continue;
    }

    // Multi-char operators
    const two = code.slice(i, i + 2);
    if (['<<', '>>', '++', '--', '+=', '-=', '*=', '/=', '==', '!=', '<=', '>=', '&&', '||', '::'].includes(two)) {
      tokens.push({ type: 'op', value: two, line });
      i += 2;
      continue;
    }

    // Single-char punctuation and ops
    if (['+', '-', '*', '/', '%', '<', '>', '=', '!', '&', '|'].includes(ch)) {
      tokens.push({ type: 'op', value: ch, line });
      i++;
      continue;
    }

    if ([';', '{', '}', '(', ')', '[', ']', ',', ':'].includes(ch)) {
      tokens.push({ type: 'punct', value: ch, line });
      i++;
      continue;
    }

    throw new Error(`ParseError: unexpected character '${ch}' at line ${line}`);
  }

  return tokens;
}

export function runCppLite(code: string): ExecutionResult {
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
    if (stdoutArr.join('').length > MAX_OUTPUT_CHARS) {
      throw new Error('OutputLimitExceeded: Program produced too much output.');
    }
  }

  try {
    // Check brace balance first
    let braceCount = 0;
    for (let c = 0; c < code.length; c++) {
      if (code[c] === '{') braceCount++;
      else if (code[c] === '}') {
        braceCount--;
        if (braceCount < 0) throw new Error("SyntaxError: unexpected '}'");
      }
    }
    if (braceCount > 0) {
      throw new Error("SyntaxError: expected '}'");
    }

    const tokens = tokenizeCpp(code);
    const scope: Scope = {};
    let pos = 0;

    function peek(): CppToken | undefined {
      return tokens[pos];
    }

    function next(): CppToken {
      const t = tokens[pos];
      if (!t) throw new Error("Unexpected end of code");
      pos++;
      return t;
    }

    // Evaluate expressions within C++ (reusing expr.ts)
    function evalTokens(exprTokens: CppToken[]): unknown {
      if (exprTokens.length === 0) return undefined;
      // Rebuild expression string
      const exprStr = exprTokens.map((t) => {
        if (t.type === 'string') return JSON.stringify(t.value);
        return t.value;
      }).join(' ');
      return parseAndEvalExpr(exprStr, scope, 'cpp');
    }

    function executeStatementOrBlock(): void {
      countStep();
      const t = peek();
      if (!t) return;

      // Skip empty statements
      if (t.type === 'punct' && t.value === ';') {
        next();
        return;
      }

      // Block { ... }
      if (t.type === 'punct' && t.value === '{') {
        next(); // consume '{'
        while (peek() && !(peek()?.type === 'punct' && peek()?.value === '}')) {
          executeStatementOrBlock();
        }
        if (!peek() || peek()?.value !== '}') {
          throw new Error("SyntaxError: expected '}'");
        }
        next(); // consume '}'
        return;
      }

      // Check preprocessor #include or directives (if tokenized or ignored)
      // If we see #include or using namespace std;
      if (t.type === 'ident' && t.value === 'using') {
        // consume until ';'
        while (peek() && !(peek()?.type === 'punct' && peek()?.value === ';')) {
          next();
        }
        if (peek()?.value === ';') next();
        return;
      }

      // Functions: int main() { ... }
      if (t.type === 'ident' && (t.value === 'int' || t.value === 'void')) {
        const nextT = tokens[pos + 1];
        if (nextT && nextT.type === 'ident' && nextT.value === 'main') {
          next(); // type
          next(); // main
          if (peek()?.value === '(') {
            next();
            while (peek() && peek()?.value !== ')') next();
            if (peek()?.value === ')') next();
          }
          executeStatementOrBlock();
          return;
        }
      }

      // return statement: return 0;
      if (t.type === 'ident' && t.value === 'return') {
        next();
        while (peek() && peek()?.value !== ';') next();
        if (peek()?.value === ';') next();
        return;
      }

      // If statement: if (...) statement [else statement]
      if (t.type === 'ident' && t.value === 'if') {
        next(); // consume 'if'
        if (peek()?.value !== '(') throw new Error("SyntaxError: expected '(' after 'if'");
        next(); // '('
        const condTokens: CppToken[] = [];
        let pDepth = 1;
        while (peek() && pDepth > 0) {
          const pt = next();
          if (pt.value === '(') pDepth++;
          else if (pt.value === ')') {
            pDepth--;
            if (pDepth === 0) break;
          }
          condTokens.push(pt);
        }
        const cond = Boolean(evalTokens(condTokens));

        // Skip to body
        if (cond) {
          executeStatementOrBlock();
          if (peek() && peek()?.type === 'ident' && peek()?.value === 'else') {
            next(); // consume else
            skipStatementOrBlock();
          }
        } else {
          skipStatementOrBlock();
          if (peek() && peek()?.type === 'ident' && peek()?.value === 'else') {
            next(); // consume else
            executeStatementOrBlock();
          }
        }
        return;
      }

      // For loop: for (init; cond; step) body
      if (t.type === 'ident' && t.value === 'for') {
        next(); // consume 'for'
        if (peek()?.value !== '(') throw new Error("SyntaxError: expected '(' after 'for'");
        next(); // '('

        // 1. init
        const initTokens: CppToken[] = [];
        while (peek() && peek()?.value !== ';') initTokens.push(next());
        if (peek()?.value === ';') next(); // consume ';'
        if (initTokens.length > 0) {
          runDeclarationOrAssignTokens(initTokens);
        }

        // 2. cond
        const condTokens: CppToken[] = [];
        while (peek() && peek()?.value !== ';') condTokens.push(next());
        if (peek()?.value === ';') next(); // consume ';'

        // 3. step
        const stepTokens: CppToken[] = [];
        while (peek() && peek()?.value !== ')') stepTokens.push(next());
        if (peek()?.value === ')') next(); // consume ')'

        // Capture body tokens to replay
        const bodyTokens = captureStatementOrBlockTokens();

        while (true) {
          countStep();
          if (condTokens.length > 0) {
            const cond = Boolean(evalTokens(condTokens));
            if (!cond) break;
          }

          // Execute body tokens
          executeTokenSlice(bodyTokens);

          // Step
          if (stepTokens.length > 0) {
            runDeclarationOrAssignTokens(stepTokens);
          }
        }
        return;
      }

      // Cout statement: cout << ... << endl; or std::cout << ...;
      if (
        (t.type === 'ident' && t.value === 'cout') ||
        (t.type === 'ident' && t.value === 'std' && tokens[pos + 1]?.value === '::' && tokens[pos + 2]?.value === 'cout')
      ) {
        if (t.value === 'std') {
          next(); // std
          next(); // ::
        }
        next(); // cout

        // Expect chain of << expr
        while (peek() && peek()?.value === '<<') {
          next(); // consume '<<'
          // collect until next '<<' or ';'
          const exprTokens: CppToken[] = [];
          let pDepth = 0;
          while (peek()) {
            if (pDepth === 0 && (peek()?.value === '<<' || peek()?.value === ';')) break;
            const cur = next();
            if (cur.value === '(') pDepth++;
            else if (cur.value === ')') pDepth--;
            exprTokens.push(cur);
          }

          if (exprTokens.length === 1 && (exprTokens[0].value === 'endl' || (exprTokens[0].value === 'std' && tokens[pos]?.value === '::'))) {
            appendOutput('\n');
          } else {
            const val = evalTokens(exprTokens);
            if (val !== undefined) {
              appendOutput(String(val));
            }
          }
        }

        if (peek()?.value === ';') next();
        return;
      }

      // Variable declaration or assignment: int x = 3; or x += 2;
      const stmtTokens: CppToken[] = [];
      while (peek() && peek()?.value !== ';') {
        stmtTokens.push(next());
      }
      if (peek()?.value === ';') next();
      runDeclarationOrAssignTokens(stmtTokens);
    }

    function runDeclarationOrAssignTokens(tokensList: CppToken[]): void {
      if (tokensList.length === 0) return;
      let startIdx = 0;
      const first = tokensList[0].value;
      if (['int', 'string', 'bool', 'double', 'float', 'auto'].includes(first)) {
        startIdx = 1;
      }
      if (startIdx >= tokensList.length) return;

      const varName = tokensList[startIdx].value;

      // Handle ++ or --: i++ or ++i
      if (tokensList.length === startIdx + 2 && tokensList[startIdx + 1].value === '++') {
        const cur = Number(scope[varName] ?? 0);
        scope[varName] = cur + 1;
        return;
      }
      if (tokensList.length === startIdx + 2 && tokensList[startIdx + 1].value === '--') {
        const cur = Number(scope[varName] ?? 0);
        scope[varName] = cur - 1;
        return;
      }

      // Handle = += -= *= /=
      if (startIdx + 1 < tokensList.length) {
        const op = tokensList[startIdx + 1].value;
        const rhsTokens = tokensList.slice(startIdx + 2);
        const rhs = evalTokens(rhsTokens);

        if (op === '=') {
          scope[varName] = rhs;
        } else if (op === '+=') {
          const cur = scope[varName];
          if (cur === undefined) throw new Error(`NameError: '${varName}' was not declared`);
          if (typeof cur === 'string' || typeof rhs === 'string') {
            scope[varName] = `${cur}${rhs}`;
          } else {
            scope[varName] = (cur as number) + (rhs as number);
          }
        } else if (op === '-=') {
          scope[varName] = (scope[varName] as number) - (rhs as number);
        } else if (op === '*=') {
          scope[varName] = (scope[varName] as number) * (rhs as number);
        } else if (op === '/=') {
          scope[varName] = Math.floor((scope[varName] as number) / (rhs as number));
        }
      }
    }

    function skipStatementOrBlock(): void {
      const t = peek();
      if (!t) return;
      if (t.value === '{') {
        next();
        let depth = 1;
        while (peek() && depth > 0) {
          const cur = next();
          if (cur.value === '{') depth++;
          else if (cur.value === '}') depth--;
        }
      } else {
        while (peek() && peek()?.value !== ';') next();
        if (peek()?.value === ';') next();
      }
    }

    function captureStatementOrBlockTokens(): CppToken[] {
      const captured: CppToken[] = [];
      const t = peek();
      if (!t) return captured;
      if (t.value === '{') {
        captured.push(next());
        let depth = 1;
        while (peek() && depth > 0) {
          const cur = next();
          captured.push(cur);
          if (cur.value === '{') depth++;
          else if (cur.value === '}') depth--;
        }
      } else {
        while (peek() && peek()?.value !== ';') {
          captured.push(next());
        }
        if (peek()?.value === ';') captured.push(next());
      }
      return captured;
    }

    function executeTokenSlice(tList: CppToken[]): void {
      let subPos = 0;
      function subPeek(): CppToken | undefined {
        return tList[subPos];
      }
      function subNext(): CppToken {
        const t = tList[subPos];
        if (!t) throw new Error("Unexpected end of code");
        subPos++;
        return t;
      }

      function execSubStatement(): void {
        countStep();
        const t = subPeek();
        if (!t) return;

        if (t.type === 'punct' && t.value === ';') {
          subNext();
          return;
        }

        if (t.type === 'punct' && t.value === '{') {
          subNext();
          while (subPeek() && !(subPeek()?.type === 'punct' && subPeek()?.value === '}')) {
            execSubStatement();
          }
          if (subPeek()?.value === '}') subNext();
          return;
        }

        // Cout statement: cout << ...
        if (
          (t.type === 'ident' && t.value === 'cout') ||
          (t.type === 'ident' && t.value === 'std' && tList[subPos + 1]?.value === '::' && tList[subPos + 2]?.value === 'cout')
        ) {
          if (t.value === 'std') {
            subNext(); // std
            subNext(); // ::
          }
          subNext(); // cout

          while (subPeek() && subPeek()?.value === '<<') {
            subNext(); // '<<'
            const exprTokens: CppToken[] = [];
            let pDepth = 0;
            while (subPeek()) {
              if (pDepth === 0 && (subPeek()?.value === '<<' || subPeek()?.value === ';')) break;
              const cur = subNext();
              if (cur.value === '(') pDepth++;
              else if (cur.value === ')') pDepth--;
              exprTokens.push(cur);
            }

            if (exprTokens.length === 1 && (exprTokens[0].value === 'endl' || (exprTokens[0].value === 'std' && tList[subPos]?.value === '::'))) {
              appendOutput('\n');
            } else {
              const val = evalTokens(exprTokens);
              if (val !== undefined) {
                appendOutput(String(val));
              }
            }
          }

          if (subPeek()?.value === ';') subNext();
          return;
        }

        // Variable assignment / declaration: total += i;
        const stmtTokens: CppToken[] = [];
        while (subPeek() && subPeek()?.value !== ';') {
          stmtTokens.push(subNext());
        }
        if (subPeek()?.value === ';') subNext();
        runDeclarationOrAssignTokens(stmtTokens);
      }

      while (subPos < tList.length) {
        execSubStatement();
      }
    }

    while (pos < tokens.length) {
      executeStatementOrBlock();
    }

    return {
      stdout: stdoutArr.join(''),
      stderr: '',
      ok: true,
    };
  } catch (err) {
    return {
      stdout: stdoutArr.join(''),
      stderr: err instanceof Error ? err.message : String(err),
      ok: false,
    };
  }
}
