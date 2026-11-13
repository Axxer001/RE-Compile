import type { Language } from '../types';
import type { Bag, Snippet, SnippetId } from './types';

export const SNIPPETS: Record<SnippetId, Snippet> = {
  // ================= Python (py.*) =================
  'py.hello': { id: 'py.hello', lang: 'python', text: 'print("Hello, World")', tier: 1, unique: true },
  'py.x3': { id: 'py.x3', lang: 'python', text: 'x = 3', tier: 1 },
  'py.y5': { id: 'py.y5', lang: 'python', text: 'y = 5', tier: 1 },
  'py.psum': { id: 'py.psum', lang: 'python', text: 'print(x + y)', tier: 1 },
  'py.for3': { id: 'py.for3', lang: 'python', text: 'for i in range(3):', tier: 2 },
  'py.pi': { id: 'py.pi', lang: 'python', text: '    print(i)', tier: 2 },
  'py.x5': { id: 'py.x5', lang: 'python', text: 'x = 5', tier: 2 },
  'py.if': { id: 'py.if', lang: 'python', text: 'if x > 2:', tier: 2 },
  'py.pbig': { id: 'py.pbig', lang: 'python', text: '    print("big")', tier: 2 },
  'py.else': { id: 'py.else', lang: 'python', text: 'else:', tier: 2 },
  'py.psmall': { id: 'py.psmall', lang: 'python', text: '    print("small")', tier: 2 },
  'py.t0': { id: 'py.t0', lang: 'python', text: 'total = 0', tier: 3 },
  'py.for4': { id: 'py.for4', lang: 'python', text: 'for i in range(4):', tier: 3 },
  'py.acc': { id: 'py.acc', lang: 'python', text: '    total += i', tier: 3 },
  'py.ptot': { id: 'py.ptot', lang: 'python', text: 'print(total)', tier: 3 },
  'py.name': { id: 'py.name', lang: 'python', text: 'name = "Ada"', tier: 3 },
  'py.greet': { id: 'py.greet', lang: 'python', text: 'print(f"Hi {name}")', tier: 3 },
  // Python Decoys
  'py.decoy.px': { id: 'py.decoy.px', lang: 'python', text: 'print(x)', tier: 1 },
  'py.decoy.for2': { id: 'py.decoy.for2', lang: 'python', text: 'for i in range(2):', tier: 2 },
  'py.decoy.y2': { id: 'py.decoy.y2', lang: 'python', text: 'y = 2', tier: 1 },

  // ================= C++ (cpp.*) =================
  'cpp.hello': { id: 'cpp.hello', lang: 'cpp', text: 'std::cout << "Hello, World";', tier: 1, unique: true },
  'cpp.x3': { id: 'cpp.x3', lang: 'cpp', text: 'int x = 3;', tier: 1 },
  'cpp.y5': { id: 'cpp.y5', lang: 'cpp', text: 'int y = 5;', tier: 1 },
  'cpp.psum': { id: 'cpp.psum', lang: 'cpp', text: 'cout << x + y << endl;', tier: 1 },
  'cpp.for3': { id: 'cpp.for3', lang: 'cpp', text: 'for (int i = 0; i < 3; i++) {', tier: 2 },
  'cpp.pi': { id: 'cpp.pi', lang: 'cpp', text: '  cout << i << endl;', tier: 2 },
  'cpp.close': { id: 'cpp.close', lang: 'cpp', text: '}', tier: 2 },
  'cpp.x5': { id: 'cpp.x5', lang: 'cpp', text: 'int x = 5;', tier: 2 },
  'cpp.if': { id: 'cpp.if', lang: 'cpp', text: 'if (x > 2) {', tier: 2 },
  'cpp.pbig': { id: 'cpp.pbig', lang: 'cpp', text: '  cout << "big" << endl;', tier: 2 },
  'cpp.else': { id: 'cpp.else', lang: 'cpp', text: '} else {', tier: 2 },
  'cpp.psmall': { id: 'cpp.psmall', lang: 'cpp', text: '  cout << "small" << endl;', tier: 2 },
  'cpp.t0': { id: 'cpp.t0', lang: 'cpp', text: 'int total = 0;', tier: 3 },
  'cpp.for4': { id: 'cpp.for4', lang: 'cpp', text: 'for (int i = 0; i < 4; i++) {', tier: 3 },
  'cpp.acc': { id: 'cpp.acc', lang: 'cpp', text: '  total += i;', tier: 3 },
  'cpp.ptot': { id: 'cpp.ptot', lang: 'cpp', text: 'cout << total << endl;', tier: 3 },
  'cpp.name': { id: 'cpp.name', lang: 'cpp', text: 'string name = "Ada";', tier: 3 },
  'cpp.greet': { id: 'cpp.greet', lang: 'cpp', text: 'cout << "Hi " << name << endl;', tier: 3 },
  // C++ Decoys
  'cpp.decoy.px': { id: 'cpp.decoy.px', lang: 'cpp', text: 'cout << x << endl;', tier: 1 },
  'cpp.decoy.for2': { id: 'cpp.decoy.for2', lang: 'cpp', text: 'for (int i = 0; i < 2; i++) {', tier: 2 },
  'cpp.decoy.y2': { id: 'cpp.decoy.y2', lang: 'cpp', text: 'int y = 2;', tier: 1 },

  // ================= JavaScript (js.*) =================
  'js.hello': { id: 'js.hello', lang: 'javascript', text: 'console.log("Hello, World");', tier: 1, unique: true },
  'js.x3': { id: 'js.x3', lang: 'javascript', text: 'let x = 3;', tier: 1 },
  'js.y5': { id: 'js.y5', lang: 'javascript', text: 'let y = 5;', tier: 1 },
  'js.psum': { id: 'js.psum', lang: 'javascript', text: 'console.log(x + y);', tier: 1 },
  'js.for3': { id: 'js.for3', lang: 'javascript', text: 'for (let i = 0; i < 3; i++) {', tier: 2 },
  'js.pi': { id: 'js.pi', lang: 'javascript', text: '  console.log(i);', tier: 2 },
  'js.close': { id: 'js.close', lang: 'javascript', text: '}', tier: 2 },
  'js.x5': { id: 'js.x5', lang: 'javascript', text: 'let x = 5;', tier: 2 },
  'js.if': { id: 'js.if', lang: 'javascript', text: 'if (x > 2) {', tier: 2 },
  'js.pbig': { id: 'js.pbig', lang: 'javascript', text: '  console.log("big");', tier: 2 },
  'js.else': { id: 'js.else', lang: 'javascript', text: '} else {', tier: 2 },
  'js.psmall': { id: 'js.psmall', lang: 'javascript', text: '  console.log("small");', tier: 2 },
  'js.t0': { id: 'js.t0', lang: 'javascript', text: 'let total = 0;', tier: 3 },
  'js.for4': { id: 'js.for4', lang: 'javascript', text: 'for (let i = 0; i < 4; i++) {', tier: 3 },
  'js.acc': { id: 'js.acc', lang: 'javascript', text: '  total += i;', tier: 3 },
  'js.ptot': { id: 'js.ptot', lang: 'javascript', text: 'console.log(total);', tier: 3 },
  'js.name': { id: 'js.name', lang: 'javascript', text: 'const name = "Ada";', tier: 3 },
  'js.greet': { id: 'js.greet', lang: 'javascript', text: 'console.log(`Hi ${name}`);', tier: 3 },
  // JavaScript Decoys
  'js.decoy.px': { id: 'js.decoy.px', lang: 'javascript', text: 'console.log(x);', tier: 1 },
  'js.decoy.for2': { id: 'js.decoy.for2', lang: 'javascript', text: 'for (let i = 0; i < 2; i++) {', tier: 2 },
  'js.decoy.y2': { id: 'js.decoy.y2', lang: 'javascript', text: 'let y = 2;', tier: 1 },

  // ================= SQL (sql.*) =================
  'sql.hello': { id: 'sql.hello', lang: 'sql', text: 'SELECT "Hello, World";', tier: 1, unique: true },
  'sql.sum': { id: 'sql.sum', lang: 'sql', text: 'SELECT 3 + 5;', tier: 1 },
  'sql.u0': { id: 'sql.u0', lang: 'sql', text: 'SELECT 0', tier: 2 },
  'sql.u1': { id: 'sql.u1', lang: 'sql', text: 'UNION ALL SELECT 1', tier: 2 },
  'sql.u2': { id: 'sql.u2', lang: 'sql', text: 'UNION ALL SELECT 2;', tier: 2 },
  'sql.case': { id: 'sql.case', lang: 'sql', text: 'SELECT CASE WHEN 5 > 2', tier: 2 },
  'sql.then': { id: 'sql.then', lang: 'sql', text: "THEN 'big'", tier: 2 },
  'sql.else': { id: 'sql.else', lang: 'sql', text: "ELSE 'small'", tier: 2 },
  'sql.end': { id: 'sql.end', lang: 'sql', text: 'END;', tier: 2 },
  'sql.from': { id: 'sql.from', lang: 'sql', text: 'SELECT SUM(n) FROM (', tier: 3 },
  'sql.s0': { id: 'sql.s0', lang: 'sql', text: '  SELECT 0 AS n', tier: 3 },
  'sql.s1': { id: 'sql.s1', lang: 'sql', text: '  UNION ALL SELECT 1', tier: 3 },
  'sql.s2': { id: 'sql.s2', lang: 'sql', text: '  UNION ALL SELECT 2', tier: 3 },
  'sql.s3': { id: 'sql.s3', lang: 'sql', text: '  UNION ALL SELECT 3', tier: 3 },
  'sql.from_end': { id: 'sql.from_end', lang: 'sql', text: ');', tier: 3 },
  'sql.concat_hi': { id: 'sql.concat_hi', lang: 'sql', text: "SELECT 'Hi ' ||", tier: 3 },
  'sql.concat_ada': { id: 'sql.concat_ada', lang: 'sql', text: "'Ada';", tier: 3 },
  // SQL Decoys
  'sql.decoy.sum2': { id: 'sql.decoy.sum2', lang: 'sql', text: 'SELECT 2 + 2;', tier: 1 },
  'sql.decoy.u3': { id: 'sql.decoy.u3', lang: 'sql', text: 'UNION ALL SELECT 3;', tier: 2 },
  'sql.decoy.else': { id: 'sql.decoy.else', lang: 'sql', text: "ELSE 'other'", tier: 2 },
};

export function snippetsFor(lang: Language): Snippet[] {
  return Object.values(SNIPPETS).filter((s) => s.lang === lang);
}

export function starterSnippetId(lang: Language): SnippetId {
  switch (lang) {
    case 'python':
      return 'py.hello';
    case 'cpp':
      return 'cpp.hello';
    case 'javascript':
      return 'js.hello';
    case 'sql':
      return 'sql.hello';
  }
}

export function createStartingBag(lang: Language): Bag {
  const starter = starterSnippetId(lang);
  return { [starter]: 1 };
}
