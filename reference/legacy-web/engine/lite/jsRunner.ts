import type { ExecutionResult } from '../../types';
import { MAX_OUTPUT_CHARS, WORKER_TIMEOUT_MS } from './limits';

export async function runJsInWorker(code: string): Promise<ExecutionResult> {
  // If Worker is not available (e.g. Node.js vitest environment)
  if (typeof Worker === 'undefined') {
    return runJsSynchronously(code);
  }

  return new Promise((resolve) => {
    let worker: Worker | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;

    try {
      worker = new Worker(new URL('./jsWorker.ts', import.meta.url), {
        type: 'module',
      });
    } catch {
      // Fallback if URL resolution fails
      return resolve(runJsSynchronously(code));
    }

    timer = setTimeout(() => {
      if (worker) {
        worker.terminate();
        worker = null;
      }
      resolve({
        stdout: '',
        stderr: 'TimeLimitExceeded: JavaScript execution timed out (1000ms limit).',
        ok: false,
      });
    }, WORKER_TIMEOUT_MS);

    worker.onmessage = (e: MessageEvent<ExecutionResult>) => {
      if (timer) clearTimeout(timer);
      if (worker) {
        worker.terminate();
        worker = null;
      }

      let res = e.data;
      if (res.stdout.length > MAX_OUTPUT_CHARS) {
        res = {
          stdout: res.stdout.slice(0, MAX_OUTPUT_CHARS),
          stderr: 'OutputLimitExceeded: Program produced too much output.',
          ok: false,
        };
      }
      resolve(res);
    };

    worker.onerror = (e) => {
      if (timer) clearTimeout(timer);
      if (worker) {
        worker.terminate();
        worker = null;
      }
      resolve({
        stdout: '',
        stderr: e.message || 'Worker runtime error.',
        ok: false,
      });
    };

    worker.postMessage({ code });
  });
}

function runJsSynchronously(code: string): ExecutionResult {
  const stdoutArr: string[] = [];
  const stderrArr: string[] = [];

  const fakeConsole = {
    log: (...args: unknown[]) => {
      stdoutArr.push(
        args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
      );
    },
    info: (...args: unknown[]) => {
      stdoutArr.push(
        args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
      );
    },
    warn: (...args: unknown[]) => {
      stdoutArr.push(
        args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
      );
    },
    error: (...args: unknown[]) => {
      stderrArr.push(
        args.map((a) => (typeof a === 'string' ? a : JSON.stringify(a))).join(' ')
      );
    },
  };

  try {
    // eslint-disable-next-line no-new-func
    const fn = new Function('console', `"use strict";\n${code}`);
    fn(fakeConsole);

    const out = stdoutArr.join('\n');
    return {
      stdout: out.length > MAX_OUTPUT_CHARS ? out.slice(0, MAX_OUTPUT_CHARS) : out,
      stderr: stderrArr.join('\n'),
      ok: stderrArr.length === 0,
    };
  } catch (err) {
    return {
      stdout: stdoutArr.join('\n'),
      stderr: err instanceof Error ? err.message : String(err),
      ok: false,
    };
  }
}
