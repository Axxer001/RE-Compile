import { describe, expect, it } from 'vitest';
import { runCode } from '../src/engine/runCode';

describe('Phase 1: Language Runtimes', () => {
  // Python tests
  describe('Python Lite', () => {
    it('executes R1: Hello, World', async () => {
      const res = await runCode('print("Hello, World")', 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hello, World');
    });

    it('executes R2: sum numbers', async () => {
      const code = `x = 3\ny = 5\nprint(x + y)`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('8');
    });

    it('executes R3: for loop count', async () => {
      const code = `for i in range(3):\n    print(i)`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('0\n1\n2');
    });

    it('executes R4: if/else branch', async () => {
      const code = `x = 5\nif x > 2:\n    print("big")\nelse:\n    print("small")`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('big');
    });

    it('executes R5: accumulate sum', async () => {
      const code = `total = 0\nfor i in range(4):\n    total += i\nprint(total)`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('6');
    });

    it('executes R6: f-string greeting', async () => {
      const code = `name = "Ada"\nprint(f"Hi {name}")`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hi Ada');
    });

    it('handles comments correctly', async () => {
      const code = `# Just a comment\nprint("active") # inline comment`;
      const res = await runCode(code, 'python');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('active');
    });

    it('fails on undefined variable with NameError', async () => {
      const res = await runCode('print(unknown_var)', 'python');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain('NameError');
    });

    it('fails on indentation errors', async () => {
      const res = await runCode('for i in range(3):\nprint(i)', 'python');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain('IndentationError');
    });
  });

  // C++ tests
  describe('C++ Lite', () => {
    it('executes R1: Hello, World', async () => {
      const code = `#include <iostream>\nusing namespace std;\nint main() {\n  cout << "Hello, World";\n  return 0;\n}`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hello, World');
    });

    it('executes R2: sum numbers', async () => {
      const code = `int x = 3;\nint y = 5;\ncout << x + y << endl;`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout.trim()).toBe('8');
    });

    it('executes R3: for loop count', async () => {
      const code = `for (int i = 0; i < 3; i++) {\n  cout << i << endl;\n}`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout.trim()).toBe('0\n1\n2');
    });

    it('executes R4: if/else branch', async () => {
      const code = `int x = 5;\nif (x > 2) {\n  cout << "big" << endl;\n} else {\n  cout << "small" << endl;\n}`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout.trim()).toBe('big');
    });

    it('executes R5: accumulate sum', async () => {
      const code = `int total = 0;\nfor (int i = 0; i < 4; i++) {\n  total += i;\n}\ncout << total << endl;`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout.trim()).toBe('6');
    });

    it('executes R6: string greeting', async () => {
      const code = `string name = "Ada";\ncout << "Hi " << name << endl;`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout.trim()).toBe('Hi Ada');
    });

    it('fails when comments hide real statements', async () => {
      const code = `// cout << "Hello, World";`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('');
    });

    it('fails on unbalanced braces', async () => {
      const code = `int main() {\n  cout << "missing brace";\n`;
      const res = await runCode(code, 'cpp');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain("expected '}'");
    });
  });

  // JavaScript tests
  describe('JavaScript Runner', () => {
    it('executes R1: Hello, World', async () => {
      const res = await runCode('console.log("Hello, World");', 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hello, World');
    });

    it('executes R2: sum numbers', async () => {
      const code = `let x = 3;\nlet y = 5;\nconsole.log(x + y);`;
      const res = await runCode(code, 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('8');
    });

    it('executes R3: for loop count', async () => {
      const code = `for (let i = 0; i < 3; i++) {\n  console.log(i);\n}`;
      const res = await runCode(code, 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('0\n1\n2');
    });

    it('executes R4: if/else branch', async () => {
      const code = `let x = 5;\nif (x > 2) {\n  console.log("big");\n} else {\n  console.log("small");\n}`;
      const res = await runCode(code, 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('big');
    });

    it('executes R5: accumulate sum', async () => {
      const code = `let total = 0;\nfor (let i = 0; i < 4; i++) {\n  total += i;\n}\nconsole.log(total);`;
      const res = await runCode(code, 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('6');
    });

    it('executes R6: template string greeting', async () => {
      const code = 'const name = "Ada";\nconsole.log(`Hi ${name}`);';
      const res = await runCode(code, 'javascript');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hi Ada');
    });

    it('captures runtime exceptions cleanly', async () => {
      const res = await runCode('nonExistentFunction();', 'javascript');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain('nonExistentFunction is not defined');
    });
  });

  // SQL tests
  describe('SQL Lite', () => {
    it('executes R1: Hello, World', async () => {
      const res = await runCode('SELECT "Hello, World";', 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hello, World');
    });

    it('executes R2: sum numbers', async () => {
      const res = await runCode('SELECT 3 + 5;', 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('8');
    });

    it('executes R3: UNION ALL counting', async () => {
      const code = `SELECT 0 UNION ALL SELECT 1 UNION ALL SELECT 2;`;
      const res = await runCode(code, 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('0\n1\n2');
    });

    it('executes R4: CASE WHEN branch', async () => {
      const code = `SELECT CASE WHEN 5 > 2 THEN 'big' ELSE 'small' END;`;
      const res = await runCode(code, 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('big');
    });

    it('executes R5: SUM aggregate over derived table', async () => {
      const code = `SELECT SUM(n) FROM ( SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 );`;
      const res = await runCode(code, 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('6');
    });

    it('executes R6: string concat with ||', async () => {
      const code = `SELECT 'Hi ' || 'Ada';`;
      const res = await runCode(code, 'sql');
      expect(res.ok).toBe(true);
      expect(res.stdout).toBe('Hi Ada');
    });

    it('requires statement to end with semicolon', async () => {
      const res = await runCode('SELECT 1', 'sql');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain("SyntaxError: statement must end with ';'");
    });
  });

  // Protection and checkQuest verification
  describe('Safety & checkQuest integration', () => {
    it('halts infinite loop in Python with step limit', async () => {
      const res = await runCode('x = 0\nfor i in range(20000):\n    x += i', 'python');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain('limit exceeded');
    });

    it('halts infinite loop in C++ with step limit', async () => {
      const res = await runCode('for (int i = 0; i < 20000; i++) { int x = i; }', 'cpp');
      expect(res.ok).toBe(false);
      expect(res.stderr).toContain('limit exceeded');
    });
  });
});
