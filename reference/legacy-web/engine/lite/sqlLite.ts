import type { ExecutionResult } from '../../types';
import { parseAndEvalExpr, type Scope } from './expr';
import { MAX_OUTPUT_CHARS, MAX_STEPS, StepLimitExceededError } from './limits';

// Row representation for SQL tabular execution
export type SqlRow = Record<string, unknown>;

export interface SqlTable {
  columns: string[];
  rows: SqlRow[];
}

export function runSqlLite(code: string): ExecutionResult {
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

  try {
    // Strip comments: -- comment
    const cleanLines = code.split('\n').map((line) => {
      let clean = '';
      let inQ: string | null = null;
      for (let i = 0; i < line.length; i++) {
        const ch = line[i];
        if (inQ) {
          clean += ch;
          if (ch === inQ && line[i - 1] !== '\\') inQ = null;
        } else {
          if (ch === '"' || ch === "'") {
            inQ = ch;
            clean += ch;
          } else if (ch === '-' && line[i + 1] === '-') {
            break; // comment
          } else {
            clean += ch;
          }
        }
      }
      return clean;
    });

    const fullCode = cleanLines.join(' ').trim();
    if (!fullCode) {
      return { stdout: '', stderr: '', ok: true };
    }

    if (!fullCode.endsWith(';')) {
      throw new Error("SyntaxError: statement must end with ';'");
    }

    // Remove trailing semicolon for query execution
    const query = fullCode.slice(0, -1).trim();

    const table = executeQuery(query);

    for (const row of table.rows) {
      countStep();
      const line = table.columns.map((col) => String(row[col] ?? '')).join('|');
      appendOutput(line);
    }

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

  function executeQuery(sql: string): SqlTable {
    countStep();
    sql = sql.trim();

    // Check for UNION ALL
    // Must be split top-level (not inside parenthesis)
    const unionParts = splitTopLevel(sql, 'UNION ALL');
    if (unionParts.length > 1) {
      let combinedCols: string[] = [];
      const combinedRows: SqlRow[] = [];

      for (let pIdx = 0; pIdx < unionParts.length; pIdx++) {
        const sub = executeQuery(unionParts[pIdx]);
        if (pIdx === 0) {
          combinedCols = sub.columns;
          for (const r of sub.rows) combinedRows.push(r);
        } else {
          // Align columns to the first query's column names by index
          for (const r of sub.rows) {
            const mappedRow: SqlRow = {};
            combinedCols.forEach((colName, cIdx) => {
              const subColName = sub.columns[cIdx] ?? colName;
              mappedRow[colName] = r[subColName];
            });
            combinedRows.push(mappedRow);
          }
        }
      }

      return { columns: combinedCols, rows: combinedRows };
    }

    // Check SELECT ... [FROM ( ... )]
    // Top level FROM
    const fromIdx = findTopLevelKeyword(sql, 'FROM');
    let selectClause = sql;
    let fromSource: SqlTable | null = null;

    if (fromIdx !== -1) {
      selectClause = sql.substring(0, fromIdx).trim();
      const fromClause = sql.substring(fromIdx + 4).trim();

      // Check derived table: ( subquery ) [AS alias]
      if (fromClause.startsWith('(')) {
        // Find matching closing paren
        let depth = 0;
        let closeIdx = -1;
        let inQ: string | null = null;
        for (let i = 0; i < fromClause.length; i++) {
          const ch = fromClause[i];
          if (inQ) {
            if (ch === inQ && fromClause[i - 1] !== '\\') inQ = null;
          } else {
            if (ch === '"' || ch === "'") inQ = ch;
            else if (ch === '(') depth++;
            else if (ch === ')') {
              depth--;
              if (depth === 0) {
                closeIdx = i;
                break;
              }
            }
          }
        }

        if (closeIdx === -1) throw new Error("SyntaxError: unmatched '(' in FROM clause");
        const subQuery = fromClause.slice(1, closeIdx).trim();
        fromSource = executeQuery(subQuery);
      } else {
        throw new Error(`SyntaxError: unsupported table source in FROM: ${fromClause}`);
      }
    }

    // Now evaluate SELECT clause: SELECT col1, col2 AS alias ...
    const selectMatch = selectClause.match(/^SELECT\s+(.*)$/i);
    if (!selectMatch) {
      throw new Error(`SyntaxError: query must begin with SELECT: ${selectClause}`);
    }

    const itemsStr = selectMatch[1].trim();
    const selectItems = splitTopLevel(itemsStr, ',');

    // If there is a FROM source table
    if (fromSource) {
      // Check if there are aggregate functions: SUM(col), COUNT(col), MIN, MAX
      const isAggregate = selectItems.some((item) =>
        /\b(SUM|COUNT|MIN|MAX)\s*\(/i.test(item)
      );

      if (isAggregate) {
        const outRow: SqlRow = {};
        const outCols: string[] = [];

        selectItems.forEach((item, idx) => {
          const { expr, alias } = parseSelectItem(item, `col_${idx}`);
          outCols.push(alias);

          const aggMatch = expr.match(/^\s*(SUM|COUNT|MIN|MAX)\s*\(\s*(.*?)\s*\)\s*$/i);
          if (aggMatch) {
            const func = aggMatch[1].toUpperCase();
            const colExpr = aggMatch[2];

            const values = fromSource!.rows.map((row) =>
              parseAndEvalExpr(colExpr, row as Scope, 'sql')
            );

            if (func === 'COUNT') {
              outRow[alias] = values.filter((v) => v !== null && v !== undefined).length;
            } else if (func === 'SUM') {
              outRow[alias] = values.reduce<number>((acc, v) => acc + Number(v ?? 0), 0);
            } else if (func === 'MIN') {
              outRow[alias] = Math.min(...values.map(Number));
            } else if (func === 'MAX') {
              outRow[alias] = Math.max(...values.map(Number));
            }
          } else {
            // Non-aggregate in aggregate query
            outRow[alias] = parseAndEvalExpr(expr, fromSource!.rows[0] as Scope, 'sql');
          }
        });

        return { columns: outCols, rows: [outRow] };
      }

      // Non-aggregate select over rows
      const outCols: string[] = [];
      const outRows: SqlRow[] = fromSource.rows.map((row) => {
        const r: SqlRow = {};
        selectItems.forEach((item, idx) => {
          const { expr, alias } = parseSelectItem(item, `col_${idx}`);
          if (!outCols.includes(alias)) outCols.push(alias);
          r[alias] = parseAndEvalExpr(expr, row as Scope, 'sql');
        });
        return r;
      });

      return { columns: outCols, rows: outRows };
    }

    // No FROM source: single row evaluated from expressions
    const outRow: SqlRow = {};
    const outCols: string[] = [];

    selectItems.forEach((item, idx) => {
      const { expr, alias } = parseSelectItem(item, `col_${idx}`);
      outCols.push(alias);
      outRow[alias] = evaluateSqlExpr(expr, {});
    });

    return { columns: outCols, rows: [outRow] };
  }

  function evaluateSqlExpr(expr: string, scope: Scope): unknown {
    expr = expr.trim();

    // Check for CASE WHEN ... THEN ... ELSE ... END
    const caseMatch = expr.match(/^CASE\s+(.*?)\s+END$/is);
    if (caseMatch) {
      const inner = caseMatch[1].trim();
      // Match WHEN cond THEN val ... ELSE val
      const whenParts: { cond: string; result: string }[] = [];
      let elsePart: string | null = null;

      // Extract ELSE if present
      const elseIdx = findTopLevelKeyword(inner, 'ELSE');
      let whenSection = inner;
      if (elseIdx !== -1) {
        whenSection = inner.substring(0, elseIdx).trim();
        elsePart = inner.substring(elseIdx + 4).trim();
      }

      // Extract all WHEN ... THEN ...
      const whenRegex = /WHEN\s+(.*?)\s+THEN\s+(.*?)(?=(WHEN|$))/gis;
      let wm: RegExpExecArray | null;
      while ((wm = whenRegex.exec(whenSection)) !== null) {
        whenParts.push({ cond: wm[1].trim(), result: wm[2].trim() });
      }

      for (const part of whenParts) {
        const condVal = parseAndEvalExpr(part.cond, scope, 'sql');
        if (Boolean(condVal)) {
          return parseAndEvalExpr(part.result, scope, 'sql');
        }
      }

      if (elsePart !== null) {
        return parseAndEvalExpr(elsePart, scope, 'sql');
      }

      return null;
    }

    return parseAndEvalExpr(expr, scope, 'sql');
  }

  function parseSelectItem(item: string, defaultAlias: string): { expr: string; alias: string } {
    const asIdx = findTopLevelKeyword(item, 'AS');
    if (asIdx !== -1) {
      const expr = item.substring(0, asIdx).trim();
      const alias = item.substring(asIdx + 2).trim();
      return { expr, alias };
    }
    return { expr: item.trim(), alias: defaultAlias };
  }

  function findTopLevelKeyword(str: string, keyword: string): number {
    let inQ: string | null = null;
    let depth = 0;
    const len = keyword.length;

    for (let i = 0; i <= str.length - len; i++) {
      const ch = str[i];
      if (inQ) {
        if (ch === inQ && str[i - 1] !== '\\') inQ = null;
      } else {
        if (ch === '"' || ch === "'") {
          inQ = ch;
        } else if (ch === '(') {
          depth++;
        } else if (ch === ')') {
          depth--;
        } else if (depth === 0) {
          // Check keyword boundary
          const sub = str.substr(i, len);
          if (sub.toUpperCase() === keyword.toUpperCase()) {
            const prevChar = i > 0 ? str[i - 1] : ' ';
            const nextChar = i + len < str.length ? str[i + len] : ' ';
            if (/\s|[(),]/.test(prevChar) && /\s|[(),]/.test(nextChar)) {
              return i;
            }
          }
        }
      }
    }
    return -1;
  }

  function splitTopLevel(str: string, delimiter: string): string[] {
    const parts: string[] = [];
    let cur = '';
    let inQ: string | null = null;
    let depth = 0;
    const dLen = delimiter.length;

    let i = 0;
    while (i < str.length) {
      const ch = str[i];
      if (inQ) {
        cur += ch;
        if (ch === inQ && str[i - 1] !== '\\') inQ = null;
        i++;
      } else {
        if (ch === '"' || ch === "'") {
          inQ = ch;
          cur += ch;
          i++;
        } else if (ch === '(') {
          depth++;
          cur += ch;
          i++;
        } else if (ch === ')') {
          depth--;
          cur += ch;
          i++;
        } else if (depth === 0) {
          const sub = str.substr(i, dLen);
          if (sub.toUpperCase() === delimiter.toUpperCase()) {
            // Check boundary if alphabet delimiter
            let isDelim = true;
            if (/[A-Z]/.test(delimiter.toUpperCase())) {
              const prev = i > 0 ? str[i - 1] : ' ';
              const next = i + dLen < str.length ? str[i + dLen] : ' ';
              if (!/\s/.test(prev) || !/\s/.test(next)) isDelim = false;
            }
            if (isDelim) {
              parts.push(cur.trim());
              cur = '';
              i += dLen;
              continue;
            }
          }
          cur += ch;
          i++;
        } else {
          cur += ch;
          i++;
        }
      }
    }

    if (cur.trim()) parts.push(cur.trim());
    return parts;
  }
}
