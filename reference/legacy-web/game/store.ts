import type { HudSnapshot } from './types';

export type Listener = () => void;

export class GameStore {
  private state: HudSnapshot;
  private listeners: Set<Listener> = new Set();
  private lastFlush = 0;
  private dirty = false;

  constructor(initialState: HudSnapshot) {
    this.state = initialState;
  }

  get = (): HudSnapshot => {
    return this.state;
  };

  subscribe = (listener: Listener): (() => void) => {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  };

  /**
   * Updates state. If immediate is true, listeners are notified synchronously.
   * Otherwise marked dirty for 10 Hz throttled flush.
   */
  set(partial: Partial<HudSnapshot>, immediate = false): void {
    let changed = false;
    for (const key of Object.keys(partial) as (keyof HudSnapshot)[]) {
      if (this.state[key] !== partial[key]) {
        changed = true;
        break;
      }
    }

    if (!changed) return;

    this.state = {
      ...this.state,
      ...partial,
    };

    if (immediate) {
      this.notify();
    } else {
      this.dirty = true;
    }
  }

  /**
   * Throttled flush called from animation frame loop (<= 10 Hz = 100ms interval).
   */
  flush(now: number): void {
    if (this.dirty && now - this.lastFlush >= 100) {
      this.notify();
      this.lastFlush = now;
      this.dirty = false;
    }
  }

  notify(): void {
    this.dirty = false;
    for (const listener of this.listeners) {
      listener();
    }
  }
}
