export type Dialect = 'python' | 'cpp' | 'sql' | 'js';

export type TokenType =
  | 'number'
  | 'string'
  | 'ident'
  | 'op'
  | 'punct'
  | 'eof';

export interface Token {
  type: TokenType;
  value: string;
  pos: number;
}

export interface ASTNode {
  type: string;
  [key: string]: unknown;
}

export class ParseError extends Error {
  constructor(message: string, public pos?: number) {
    super(message);
    this.name = 'ParseError';
  }
}

export function tokenize(code: string, _dialect: Dialect): Token[] {
  const tokens: Token[] = [];
  let i = 0;
  const n = code.length;

  while (i < n) {
    const ch = code[i];

    // whitespace
    if (/\s/.test(ch)) {
      i++;
      continue;
    }

    // strings
    if (ch === '"' || ch === "'") {
      const quote = ch;
      let val = '';
      const start = i;
      i++;
      while (i < n && code[i] !== quote) {
        if (code[i] === '\\' && i + 1 < n) {
          i++;
          const esc = code[i];
          if (esc === 'n') val += '\n';
          else if (esc === 't') val += '\t';
          else if (esc === 'r') val += '\r';
          else val += esc;
        } else {
          val += code[i];
        }
        i++;
      }
      if (i >= n) throw new ParseError(`Unterminated string starting at pos ${start}`, start);
      i++; // skip closing quote
      tokens.push({ type: 'string', value: val, pos: start });
      continue;
    }

    // numbers (int or float)
    if (/[0-9]/.test(ch)) {
      const start = i;
      let val = '';
      while (i < n && /[0-9.]/.test(code[i])) {
        val += code[i];
        i++;
      }
      tokens.push({ type: 'number', value: val, pos: start });
      continue;
    }

    // identifiers / keywords
    if (/[a-zA-Z_]/.test(ch)) {
      const start = i;
      let val = '';
      while (i < n && /[a-zA-Z0-9_]/.test(code[i])) {
        val += code[i];
        i++;
      }
      tokens.push({ type: 'ident', value: val, pos: start });
      continue;
    }

    // multi-character operators: ==, !=, <=, >=, //, +=, -=, *=, ++, --, &&, ||, <<
    const two = code.slice(i, i + 2);
    if (['==', '!=', '<=', '>=', '//', '+=', '-=', '*=', '++', '--', '&&', '||', '<<'].includes(two)) {
      tokens.push({ type: 'op', value: two, pos: i });
      i += 2;
      continue;
    }

    // single character ops and punctuation
    if (['+', '-', '*', '/', '%', '<', '>', '=', '!', '&', '|'].includes(ch)) {
      tokens.push({ type: 'op', value: ch, pos: i });
      i++;
      continue;
    }

    if (['(', ')', '[', ']', '{', '}', ',', ';', ':', '.'].includes(ch)) {
      tokens.push({ type: 'punct', value: ch, pos: i });
      i++;
      continue;
    }

    throw new ParseError(`Unexpected character '${ch}' at pos ${i}`, i);
  }

  tokens.push({ type: 'eof', value: '', pos: n });
  return tokens;
}

// Pratt parser binding power
function getPrefixBp(op: string): number {
  if (op === '-' || op === '+' || op === 'not' || op === '!') return 70;
  return 0;
}

function getInfixBp(op: string, dialect: Dialect): [number, number] | null {
  const norm = dialect === 'sql' ? op.toUpperCase() : op;
  switch (norm) {
    case '||':
      if (dialect === 'sql') return [40, 41]; // string concat
      return [10, 11]; // logical OR
    case 'OR':
      return [10, 11];
    case '&&':
    case 'AND':
      return [15, 16];
    case '==':
    case '=':
    case '!=':
    case '<>':
      return [20, 21];
    case '<':
    case '<=':
    case '>':
    case '>=':
      return [25, 26];
    case '<<':
      return [28, 29];
    case '+':
    case '-':
      return [30, 31];
    case '*':
    case '/':
    case '//':
    case '%':
      return [40, 41];
    default:
      return null;
  }
}

export class ExprParser {
  private pos = 0;
  constructor(private tokens: Token[], private dialect: Dialect) {}

  private peek(): Token {
    return this.tokens[this.pos] || { type: 'eof', value: '', pos: -1 };
  }

  private next(): Token {
    const t = this.peek();
    this.pos++;
    return t;
  }

  parse(minBp = 0): ASTNode {
    const token = this.next();
    let left: ASTNode;

    if (token.type === 'number') {
      left = { type: 'Literal', value: Number(token.value), raw: token.value };
    } else if (token.type === 'string') {
      left = { type: 'Literal', value: token.value, raw: JSON.stringify(token.value) };
    } else if (token.type === 'ident') {
      const lower = token.value.toLowerCase();
      if ((lower === 'not' && this.dialect === 'python') || (lower === 'not' && this.dialect === 'sql')) {
        const bp = getPrefixBp('not');
        const expr = this.parse(bp);
        left = { type: 'UnaryOp', op: 'not', expr };
      } else if (lower === 'true') {
        left = { type: 'Literal', value: true };
      } else if (lower === 'false') {
        left = { type: 'Literal', value: false };
      } else if (lower === 'none' || lower === 'null') {
        left = { type: 'Literal', value: null };
      } else {
        // check for function call: ident(arg1, arg2)
        if (this.peek().type === 'punct' && this.peek().value === '(') {
          this.next(); // consume '('
          const args: ASTNode[] = [];
          if (!(this.peek().type === 'punct' && this.peek().value === ')')) {
            while (true) {
              args.push(this.parse(0));
              if (this.peek().type === 'punct' && this.peek().value === ',') {
                this.next();
                continue;
              }
              break;
            }
          }
          if (this.peek().type !== 'punct' || this.peek().value !== ')') {
            throw new ParseError(`Expected ')' after function arguments at pos ${this.peek().pos}`);
          }
          this.next(); // consume ')'
          left = { type: 'Call', callee: token.value, args };
        } else {
          left = { type: 'Identifier', name: token.value };
        }
      }
    } else if (token.type === 'op' && (token.value === '-' || token.value === '+' || token.value === '!')) {
      const bp = getPrefixBp(token.value);
      const expr = this.parse(bp);
      left = { type: 'UnaryOp', op: token.value, expr };
    } else if (token.type === 'punct' && token.value === '(') {
      left = this.parse(0);
      const close = this.next();
      if (close.type !== 'punct' || close.value !== ')') {
        throw new ParseError(`Expected closing ')' at pos ${close.pos}`);
      }
    } else {
      throw new ParseError(`Unexpected token '${token.value}' at pos ${token.pos}`);
    }

    while (true) {
      const nextToken = this.peek();
      if (nextToken.type === 'eof') break;

      let op = nextToken.value;
      if (nextToken.type === 'ident') {
        const up = nextToken.value.toUpperCase();
        if (up === 'AND' || up === 'OR') {
          op = up;
        } else {
          break;
        }
      } else if (nextToken.type !== 'op') {
        break;
      }

      const bp = getInfixBp(op, this.dialect);
      if (!bp) break;
      const [leftBp, rightBp] = bp;
      if (leftBp < minBp) break;

      this.next(); // consume operator
      const right = this.parse(rightBp);
      left = { type: 'BinaryOp', op, left, right };
    }

    return left;
  }
}

export type Scope = Record<string, unknown>;

export function evaluateAST(node: ASTNode, scope: Scope, dialect: Dialect): unknown {
  switch (node.type) {
    case 'Literal':
      return node.value;

    case 'Identifier': {
      const name = node.name as string;
      if (name in scope) return scope[name];
      if (dialect === 'cpp' && name === 'endl') return '\n';
      throw new Error(`NameError: name '${name}' is not defined`);
    }

    case 'UnaryOp': {
      const val = evaluateAST(node.expr as ASTNode, scope, dialect);
      const op = node.op as string;
      if (op === '-') return -(val as number);
      if (op === '+') return +(val as number);
      if (op === 'not' || op === '!') return !val;
      throw new Error(`Unsupported unary operator: ${op}`);
    }

    case 'BinaryOp': {
      const left = evaluateAST(node.left as ASTNode, scope, dialect);
      const right = evaluateAST(node.right as ASTNode, scope, dialect);
      const op = (node.op as string).toUpperCase();

      if (op === '+' || (op === '||' && dialect === 'sql')) {
        if (typeof left === 'string' || typeof right === 'string') {
          return `${left ?? ''}${right ?? ''}`;
        }
        return (left as number) + (right as number);
      }

      if (op === '-') return (left as number) - (right as number);
      if (op === '*') return (left as number) * (right as number);
      if (op === '/') return (left as number) / (right as number);
      if (op === '//') return Math.floor((left as number) / (right as number));
      if (op === '%') return (left as number) % (right as number);

      if (op === '==' || (op === '=' && dialect === 'sql')) return left === right;
      if (op === '!=' || op === '<>') return left !== right;
      if (op === '<') return (left as number) < (right as number);
      if (op === '<=') return (left as number) <= (right as number);
      if (op === '>') return (left as number) > (right as number);
      if (op === '>=') return (left as number) >= (right as number);

      if (op === 'AND' || op === '&&') return Boolean(left) && Boolean(right);
      if (op === 'OR' || op === '||') return Boolean(left) || Boolean(right);

      throw new Error(`Unsupported operator '${node.op}'`);
    }

    default:
      throw new Error(`Unsupported AST node type: ${node.type}`);
  }
}

export function parseAndEvalExpr(code: string, scope: Scope, dialect: Dialect): unknown {
  const tokens = tokenize(code, dialect);
  if (tokens.length === 1 && tokens[0].type === 'eof') return undefined;
  const parser = new ExprParser(tokens, dialect);
  const ast = parser.parse(0);
  return evaluateAST(ast, scope, dialect);
}
