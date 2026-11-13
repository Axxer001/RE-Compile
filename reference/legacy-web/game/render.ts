import type { CanvasPalette } from './palette';
import type { DamageNumber, EffectiveStats, Enemy, Gem, Projectile } from './types';
import type { WeaponState } from './weapons';

export interface RenderState {
  player: {
    x: number;
    y: number;
    hp: number;
    maxHp: number;
    radius: number;
    iframes: number;
  };
  stats: EffectiveStats;
  weaponState: WeaponState;
  orbitBlades: { x: number; y: number; radius: number }[];
  enemies: Enemy[];
  projectiles: Projectile[];
  gems: Gem[];
  damageNumbers: DamageNumber[];
  notices: DamageNumber[];
  caches: { x: number; y: number }[];
  bossIds: ReadonlySet<number>;
  cursor: {
    worldX: number;
    worldY: number;
    canvasX: number;
    canvasY: number;
  };
  settings: {
    reducedMotion: boolean;
    damageNumbers: boolean;
  };
}

class SpriteCache {
  private cache = new Map<string, HTMLCanvasElement>();

  getBadge(text: string, color: string, border: string, bg = '#0d1424'): HTMLCanvasElement {
    const key = `b:${text}:${color}:${border}:${bg}`;
    let canvas = this.cache.get(key);
    if (canvas) return canvas;

    canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d')!;
    ctx.font = '10px "Courier New", monospace';
    const textMetrics = ctx.measureText(text);
    const textWidth = Math.ceil(textMetrics.width);
    const padX = 6;
    const padY = 4;
    const w = textWidth + padX * 2;
    const h = 16 + padY;

    canvas.width = w;
    canvas.height = h;

    // Draw background
    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, w, h);

    // Draw border
    ctx.strokeStyle = border;
    ctx.lineWidth = 1.5;
    ctx.strokeRect(1, 1, w - 2, h - 2);

    // Draw text
    ctx.fillStyle = color;
    ctx.font = '10px "Courier New", monospace';
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText(text, w / 2, h / 2);

    this.cache.set(key, canvas);
    return canvas;
  }

  getGlyph(glyph: string, color: string, isElite: boolean, isHit: boolean): HTMLCanvasElement {
    const key = `g:${glyph}:${color}:${isElite ? 1 : 0}:${isHit ? 1 : 0}`;
    let canvas = this.cache.get(key);
    if (canvas) return canvas;

    canvas = document.createElement('canvas');
    const ctx = canvas.getContext('2d')!;
    const fontSize = isElite ? 16 : 12;
    ctx.font = `bold ${fontSize}px "Courier New", monospace`;
    const textMetrics = ctx.measureText(glyph);
    const w = Math.max(24, Math.ceil(textMetrics.width) + 8);
    const h = isElite ? 28 : 22;

    canvas.width = w;
    canvas.height = h;

    if (isHit) {
      ctx.fillStyle = '#ffffff';
      ctx.fillRect(0, 0, w, h);
      ctx.fillStyle = '#000000';
    } else {
      ctx.fillStyle = 'rgba(13, 20, 36, 0.85)';
      ctx.fillRect(0, 0, w, h);
      ctx.strokeStyle = isElite ? '#facc15' : color;
      ctx.lineWidth = isElite ? 2 : 1;
      ctx.strokeRect(1, 1, w - 2, h - 2);
      ctx.fillStyle = isElite ? '#facc15' : color;
    }

    ctx.font = `bold ${fontSize}px "Courier New", monospace`;
    ctx.textBaseline = 'middle';
    ctx.textAlign = 'center';
    ctx.fillText(glyph, w / 2, h / 2);

    this.cache.set(key, canvas);
    return canvas;
  }
}

const spriteCache = new SpriteCache();

export function renderGame(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  state: RenderState,
  palette: CanvasPalette
): void {
  // Camera centers on player
  const camX = state.player.x - width / 2;
  const camY = state.player.y - height / 2;

  // 1. Clear background
  ctx.fillStyle = palette.bg;
  ctx.fillRect(0, 0, width, height);

  // 2. Scrolling Grid
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.04)';
  ctx.lineWidth = 1;
  const gridSize = 40;
  const startX = -(((camX % gridSize) + gridSize) % gridSize);
  const startY = -(((camY % gridSize) + gridSize) % gridSize);

  ctx.beginPath();
  for (let x = startX; x < width; x += gridSize) {
    ctx.moveTo(x, 0);
    ctx.lineTo(x, height);
  }
  for (let y = startY; y < height; y += gridSize) {
    ctx.moveTo(0, y);
    ctx.lineTo(width, y);
  }
  ctx.stroke();

  // Helper for world to screen coords
  const toScreenX = (wx: number) => Math.round(wx - camX);
  const toScreenY = (wy: number) => Math.round(wy - camY);

  // 3. Gems
  for (const gem of state.gems) {
    const sx = toScreenX(gem.x);
    const sy = toScreenY(gem.y);
    if (sx < -20 || sx > width + 20 || sy < -20 || sy > height + 20) continue;

    ctx.fillStyle = gem.color;
    ctx.beginPath();
    ctx.arc(sx, sy, 4, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  // 3b. Core caches (boss drops)
  for (const cache of state.caches) {
    const sx = toScreenX(cache.x);
    const sy = toScreenY(cache.y);
    if (sx < -60 || sx > width + 60 || sy < -30 || sy > height + 30) continue;

    const badge = spriteCache.getBadge('CORE', palette.warn, palette.warn);
    ctx.drawImage(badge, sx - badge.width / 2, sy - badge.height / 2);
  }

  // 4. Pulse shockwave
  if (state.weaponState.activePulse) {
    const pulse = state.weaponState.activePulse;
    const sx = toScreenX(pulse.x);
    const sy = toScreenY(pulse.y);

    ctx.strokeStyle = palette.info;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(sx, sy, pulse.radius, 0, Math.PI * 2);
    ctx.stroke();

    const badge = spriteCache.getBadge('if()', palette.info, palette.info);
    ctx.drawImage(badge, sx - badge.width / 2, sy - pulse.radius - badge.height / 2);
  }

  // 5. Orbit blades
  for (const blade of state.orbitBlades) {
    const sx = toScreenX(blade.x);
    const sy = toScreenY(blade.y);
    const badge = spriteCache.getBadge('for()', palette.warn, palette.warn);
    ctx.drawImage(badge, sx - badge.width / 2, sy - badge.height / 2);
  }

  // 6. Projectiles
  for (const proj of state.projectiles) {
    const sx = toScreenX(proj.x);
    const sy = toScreenY(proj.y);
    if (sx < -40 || sx > width + 40 || sy < -40 || sy > height + 40) continue;

    const badge = spriteCache.getBadge(proj.label, proj.color, proj.color);
    ctx.drawImage(badge, sx - badge.width / 2, sy - badge.height / 2);
  }

  // 7. Enemies
  for (const enemy of state.enemies) {
    const sx = toScreenX(enemy.x);
    const sy = toScreenY(enemy.y);
    if (sx < -50 || sx > width + 50 || sy < -50 || sy > height + 50) continue;

    const isHit = enemy.hitTimer > 0;
    const isBoss = state.bossIds.has(enemy.id);
    const sprite = spriteCache.getGlyph(enemy.glyph, enemy.color, !!enemy.isElite || isBoss, isHit);
    const scale = isBoss ? 2 : 1;
    const spriteW = sprite.width * scale;
    const spriteH = sprite.height * scale;

    if (isBoss) {
      // Glowing ring marks the boss hitbox, with its title above
      ctx.save();
      ctx.shadowColor = palette.warn;
      ctx.shadowBlur = 15;
      ctx.strokeStyle = palette.warn;
      ctx.lineWidth = 4;
      ctx.beginPath();
      ctx.arc(sx, sy, enemy.radius, 0, Math.PI * 2);
      ctx.stroke();
      ctx.restore();

      const title = spriteCache.getBadge('GLITCH.DAEMON', palette.warn, palette.warn);
      ctx.drawImage(title, sx - title.width / 2, sy - enemy.radius - 32);
    }

    ctx.drawImage(sprite, sx - spriteW / 2, sy - spriteH / 2, spriteW, spriteH);

    // Mini HP bar for damaged, elite or boss enemies
    if (enemy.hp < enemy.maxHp || enemy.isElite || isBoss) {
      const barW = Math.max(20, enemy.radius * 2);
      const barH = 3;
      const barX = sx - barW / 2;
      const barY = sy - enemy.radius - 8;

      ctx.fillStyle = 'rgba(0, 0, 0, 0.6)';
      ctx.fillRect(barX, barY, barW, barH);

      const fillW = Math.max(0, (enemy.hp / enemy.maxHp) * barW);
      ctx.fillStyle = enemy.isElite || isBoss ? palette.warn : palette.danger;
      ctx.fillRect(barX, barY, fillW, barH);
    }
  }

  // 8. Player
  const playerScreenX = width / 2;
  const playerScreenY = height / 2;

  // Flash if iframes active
  const isPlayerFlashing = state.player.iframes > 0 && Math.floor(state.player.iframes * 20) % 2 === 0;

  if (!isPlayerFlashing) {
    // Player body
    ctx.fillStyle = palette.classColor;
    ctx.beginPath();
    ctx.arc(playerScreenX, playerScreenY, state.player.radius, 0, Math.PI * 2);
    ctx.fill();

    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.stroke();

    // Aim pointer tick
    const aimDx = state.cursor.canvasX - playerScreenX;
    const aimDy = state.cursor.canvasY - playerScreenY;
    const aimDist = Math.hypot(aimDx, aimDy);
    if (aimDist > 0) {
      const ptrDist = state.player.radius + 6;
      const px = playerScreenX + (aimDx / aimDist) * ptrDist;
      const py = playerScreenY + (aimDy / aimDist) * ptrDist;

      ctx.fillStyle = palette.accent;
      ctx.beginPath();
      ctx.arc(px, py, 3, 0, Math.PI * 2);
      ctx.fill();
    }
  }

  // 9. Floating damage numbers
  if (state.settings.damageNumbers) {
    ctx.font = '12px "Courier New", monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    for (const dn of state.damageNumbers) {
      const sx = toScreenX(dn.x);
      const sy = toScreenY(dn.y);
      const alpha = Math.max(0, dn.ttl / dn.maxTtl);
      ctx.fillStyle = dn.color;
      ctx.globalAlpha = alpha;
      ctx.fillText(dn.text, sx, sy);
    }
    ctx.globalAlpha = 1.0;
  }

  // 9b. Reward notices (always shown, independent of the damage-number setting)
  if (state.notices.length > 0) {
    ctx.font = 'bold 14px "Courier New", monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';

    for (const n of state.notices) {
      ctx.fillStyle = n.color;
      ctx.globalAlpha = Math.max(0, n.ttl / n.maxTtl);
      ctx.fillText(n.text, toScreenX(n.x), toScreenY(n.y));
    }
    ctx.globalAlpha = 1.0;
  }

  // 10. Vignette effect (if not reduced-motion)
  if (!state.settings.reducedMotion) {
    const grad = ctx.createRadialGradient(
      width / 2,
      height / 2,
      Math.min(width, height) * 0.45,
      width / 2,
      height / 2,
      Math.max(width, height) * 0.75
    );
    grad.addColorStop(0, 'rgba(10, 14, 26, 0)');
    grad.addColorStop(1, 'rgba(10, 14, 26, 0.7)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, width, height);
  }

  // 11. Crosshair at cursor
  const cx = state.cursor.canvasX;
  const cy = state.cursor.canvasY;
  ctx.strokeStyle = palette.accent;
  ctx.lineWidth = 1.5;
  const chSize = 7;
  ctx.beginPath();
  ctx.moveTo(cx - chSize, cy);
  ctx.lineTo(cx + chSize, cy);
  ctx.moveTo(cx, cy - chSize);
  ctx.lineTo(cx, cy + chSize);
  ctx.stroke();
}
