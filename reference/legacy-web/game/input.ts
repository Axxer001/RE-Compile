export interface InputState {
  moveX: number;
  moveY: number;
  aimX: number;
  aimY: number;
  mouseWorldX: number;
  mouseWorldY: number;
  isMouseDown: boolean;
}

export interface InputHandlers {
  onSpace?: () => void;
  onEscape?: () => void;
  onDigit?: (digit: number) => void;
}

export class InputManager {
  private keys: Record<string, boolean> = {};
  private canvas: HTMLCanvasElement | null = null;
  private canvasRect: DOMRect | null = null;

  mouseX = 0;
  mouseY = 0;
  isMouseDown = false;
  handlers: InputHandlers = {};

  attach(canvas: HTMLCanvasElement, win: Window = window, handlers: InputHandlers = {}) {
    this.canvas = canvas;
    this.handlers = handlers;
    this.updateRect();

    win.addEventListener('keydown', this.handleKeyDown, true);
    win.addEventListener('keyup', this.handleKeyUp, true);
    win.addEventListener('mousemove', this.handleMouseMove);
    win.addEventListener('mousedown', this.handleMouseDown);
    win.addEventListener('mouseup', this.handleMouseUp);
    win.addEventListener('blur', this.handleBlur);
    document.addEventListener('visibilitychange', this.handleVisibility);
    win.addEventListener('resize', this.updateRect);
  }

  detach() {
    window.removeEventListener('keydown', this.handleKeyDown, true);
    window.removeEventListener('keyup', this.handleKeyUp, true);
    window.removeEventListener('mousemove', this.handleMouseMove);
    window.removeEventListener('mousedown', this.handleMouseDown);
    window.removeEventListener('mouseup', this.handleMouseUp);
    window.removeEventListener('blur', this.handleBlur);
    document.removeEventListener('visibilitychange', this.handleVisibility);
    window.removeEventListener('resize', this.updateRect);
    this.clearAll();
  }

  updateRect = () => {
    if (this.canvas) {
      this.canvasRect = this.canvas.getBoundingClientRect();
    }
  };

  private isTargetInput(e: Event): boolean {
    const tag = (e.target as HTMLElement)?.tagName?.toLowerCase();
    return tag === 'input' || tag === 'textarea' || tag === 'select';
  }

  private handleKeyDown = (e: KeyboardEvent) => {
    if (this.isTargetInput(e)) return;

    if (e.code === 'Space') {
      e.preventDefault();
      if (!e.repeat) {
        if (document.activeElement instanceof HTMLElement) {
          document.activeElement.blur();
        }
        this.handlers.onSpace?.();
      }
      return;
    }

    if (e.code === 'Escape') {
      e.preventDefault();
      if (!e.repeat) this.handlers.onEscape?.();
      return;
    }

    if (['Digit1', 'Digit2', 'Digit3'].includes(e.code)) {
      if (!e.repeat) {
        const digit = parseInt(e.code.replace('Digit', ''), 10);
        this.handlers.onDigit?.(digit);
      }
    }

    if (e.code.startsWith('Arrow')) {
      e.preventDefault();
    }

    this.keys[e.code] = true;
  };

  private handleKeyUp = (e: KeyboardEvent) => {
    if (e.code === 'Space') {
      e.preventDefault();
    }
    this.keys[e.code] = false;
  };

  private handleMouseMove = (e: MouseEvent) => {
    if (!this.canvasRect) this.updateRect();
    if (!this.canvasRect) return;

    this.mouseX = e.clientX - this.canvasRect.left;
    this.mouseY = e.clientY - this.canvasRect.top;
  };

  private handleMouseDown = (e: MouseEvent) => {
    if (e.button === 0) {
      this.isMouseDown = true;
    }
  };

  private handleMouseUp = (e: MouseEvent) => {
    if (e.button === 0) {
      this.isMouseDown = false;
    }
  };

  private handleBlur = () => {
    this.clearAll();
  };

  private handleVisibility = () => {
    if (document.hidden) {
      this.clearAll();
    }
  };

  clearAll() {
    this.keys = {};
    this.isMouseDown = false;
  }

  getMovement(): { dx: number; dy: number } {
    let dx = 0;
    let dy = 0;

    if (this.keys['KeyW'] || this.keys['ArrowUp']) dy -= 1;
    if (this.keys['KeyS'] || this.keys['ArrowDown']) dy += 1;
    if (this.keys['KeyA'] || this.keys['ArrowLeft']) dx -= 1;
    if (this.keys['KeyD'] || this.keys['ArrowRight']) dx += 1;

    // Normalise diagonals
    const mag = Math.hypot(dx, dy);
    if (mag > 0) {
      dx /= mag;
      dy /= mag;
    }

    return { dx, dy };
  }

  getAimVector(centerX: number, centerY: number): { vx: number; vy: number; angle: number } {
    const rawX = this.mouseX - centerX;
    const rawY = this.mouseY - centerY;
    const mag = Math.hypot(rawX, rawY);
    if (mag === 0) return { vx: 1, vy: 0, angle: 0 };
    return {
      vx: rawX / mag,
      vy: rawY / mag,
      angle: Math.atan2(rawY, rawX),
    };
  }
}
