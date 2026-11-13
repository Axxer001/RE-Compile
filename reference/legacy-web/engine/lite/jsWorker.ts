// Dedicated Web Worker for isolated, non-blocking JavaScript execution
self.onmessage = (e: MessageEvent<{ code: string }>) => {
  const { code } = e.data;
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

    self.postMessage({
      stdout: stdoutArr.join('\n'),
      stderr: stderrArr.join('\n'),
      ok: stderrArr.length === 0,
    });
  } catch (err) {
    self.postMessage({
      stdout: stdoutArr.join('\n'),
      stderr: err instanceof Error ? err.message : String(err),
      ok: false,
    });
  }
};
