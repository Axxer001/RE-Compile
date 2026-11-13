export interface CanvasPalette {
  bg: string;
  panel: string;
  panel2: string;
  accent: string;
  accentGlow: string;
  text: string;
  muted: string;
  danger: string;
  info: string;
  warn: string;
  classColor: string;
}

export function readPalette(classColor = '#4ade80'): CanvasPalette {
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    return {
      bg: '#0a0e1a',
      panel: '#131a2e',
      panel2: '#0d1424',
      accent: '#4ade80',
      accentGlow: 'rgba(74, 222, 128, 0.4)',
      text: '#e2e8f0',
      muted: '#64748b',
      danger: '#ef4444',
      info: '#60a5fa',
      warn: '#facc15',
      classColor,
    };
  }

  const cs = getComputedStyle(document.documentElement);
  const get = (name: string, fallback: string) => cs.getPropertyValue(name).trim() || fallback;

  return {
    bg: get('--bg', '#0a0e1a'),
    panel: get('--panel', '#131a2e'),
    panel2: get('--panel-2', '#0d1424'),
    accent: get('--accent', '#4ade80'),
    accentGlow: get('--accent-glow', 'rgba(74, 222, 128, 0.4)'),
    text: get('--text', '#e2e8f0'),
    muted: get('--muted', '#64748b'),
    danger: get('--danger', '#ef4444'),
    info: get('--info', '#60a5fa'),
    warn: get('--warn', '#facc15'),
    classColor,
  };
}
