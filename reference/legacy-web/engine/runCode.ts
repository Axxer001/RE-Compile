import type { ExecutionResult, Language } from '../types';
import { runCppLite } from './lite/cppLite';
import { runJsInWorker } from './lite/jsRunner';
import { runPythonLite } from './lite/pythonLite';
import { runSqlLite } from './lite/sqlLite';

export async function runCode(code: string, language: Language): Promise<ExecutionResult> {
  switch (language) {
    case 'javascript':
      return runJsInWorker(code);
    case 'python':
      return runPythonLite(code);
    case 'cpp':
      return runCppLite(code);
    case 'sql':
      return runSqlLite(code);
    default: {
      const _exhaustive: never = language;
      return { stdout: '', stderr: `Unknown language: ${_exhaustive}`, ok: false };
    }
  }
}