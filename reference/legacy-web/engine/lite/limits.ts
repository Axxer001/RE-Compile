export const MAX_STEPS = 10_000;
export const MAX_OUTPUT_CHARS = 2_000;
export const WORKER_TIMEOUT_MS = 1_000;

export class StepLimitExceededError extends Error {
  constructor(message = 'Execution step limit exceeded (infinite loop protection).') {
    super(message);
    this.name = 'StepLimitExceededError';
  }
}
