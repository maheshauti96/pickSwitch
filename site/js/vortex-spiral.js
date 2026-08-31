/*!
 * <vortex-spiral> — VortexFlow overlay, as a drop-in web component.
 *
 * Geometry is RadialLayout.spiral from the app:
 *   8 seats / turn, 45° sweep, 0.05 rad gap, start at the top.
 *   Radius steps per seat — not per turn, and not a petal coil.
 *   Annular sectors with quadratic corner fillets (WedgeShape).
 *   Upright content box; hub carries the window title.
 *
 * Usage:
 *   <script src="/js/vortex-spiral.js" defer></script>
 *   <vortex-spiral></vortex-spiral>
 *
 * items  — recency order, item 0 nearest the hub
 * speed  — idle orbit °/s (default 2.4; 0 or `static` = off)
 * scene  — `tab-search` | `web-search` (typed query + action cards)
 */
(function () {
  'use strict';

  const D2R = Math.PI / 180;
  const R2D = 180 / Math.PI;
  const f3 = (n) => +n.toFixed(3);
  const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;'
  }[c]));
  const fav = (d, sz) =>
    `https://www.google.com/s2/favicons?domain=${encodeURIComponent(d)}&sz=${sz || 64}`;
  const pt = (r, a) => [r * Math.cos(a), r * Math.sin(a)];

  // ── RadialLayout (spiral winding), scale 1 ──────────────────────────
  const SEATS_PER_TURN = 8;
  const SWEEP = (2 * Math.PI) / SEATS_PER_TURN;
  const WEDGE_GAP = 0.05;
  const START_ANGLE = -Math.PI / 2;
  const HUB_RADIUS = 96;
  const HUB_GAP = 8;
  const FIRST_RING = HUB_RADIUS + HUB_GAP;
  const RING_THICKNESS = 120;
  const TURN_GAP = 16;
  const RADIAL_STEP = (RING_THICKNESS + TURN_GAP) / SEATS_PER_TURN;
  const CORNER = 13;
  const PADDING = 12;
  const CONTENT_MARGIN = 4;
  const PREFERRED_H = 76;
  const TITLE_PX = 12;
  const ARTWORK = 56;
  const RING_INSET = 7;
  const MINT = '#7ee8d0';
  const SEL_FILL = '#c5e8df';

  function contentSize() {
    const innerMid = FIRST_RING + RING_THICKNESS / 2;
    const ray = innerMid * Math.sin((SWEEP - WEDGE_GAP) / 2);
    const cr = Math.max(1, Math.min(RING_THICKNESS / 2, ray) - CONTENT_MARGIN);
    const diag = cr * 2;
    const height = Math.min(PREFERRED_H, diag * 0.72);
    const width = Math.sqrt(Math.max(1, diag * diag - height * height));
    return { width, height };
  }

  function seatOf(offset) {
    const slot = offset % SEATS_PER_TURN;
    const start = START_ANGLE + slot * SWEEP + WEDGE_GAP / 2;
    const end = START_ANGLE + (slot + 1) * SWEEP - WEDGE_GAP / 2;
    const inner = FIRST_RING + offset * RADIAL_STEP;
    const outer = inner + RING_THICKNESS;
    const midA = (start + end) / 2;
    const midR = (inner + outer) / 2;
    const box = contentSize();
    const [cx, cy] = pt(midR, midA);
    return {
      offset, start, end, inner, outer, midA, midR, cx, cy,
      cw: box.width, ch: box.height
    };
  }

  // WedgeShape: annular sector, quadratic fillets through the true corner.
  function wedgePath(ri, ro, a1, a2, corner) {
    const thickness = ro - ri;
    const innerArc = ri * (a2 - a1);
    const c = Math.max(0, Math.min(corner, thickness / 2, innerArc / 2));
    const p = (r, a) => {
      const [x, y] = pt(r, a);
      return `${f3(x)} ${f3(y)}`;
    };
    if (c < 0.4) {
      return `M${p(ri, a1)}A${f3(ri)} ${f3(ri)} 0 0 1 ${p(ri, a2)}L${p(ro, a2)}A${f3(ro)} ${f3(ro)} 0 0 0 ${p(ro, a1)}Z`;
    }
    const iIn = c / ri, oIn = c / ro;
    const i0 = a1 + iIn, i1 = a2 - iIn;
    const o0 = a1 + oIn, o1 = a2 - oIn;
    return [
      `M${p(ri + c, a1)}`,
      `Q${p(ri, a1)} ${p(ri, i0)}`,
      `A${f3(ri)} ${f3(ri)} 0 0 1 ${p(ri, i1)}`,
      `Q${p(ri, a2)} ${p(ri + c, a2)}`,
      `L${p(ro - c, a2)}`,
      `Q${p(ro, a2)} ${p(ro, o1)}`,
      `A${f3(ro)} ${f3(ro)} 0 0 0 ${p(ro, o0)}`,
      `Q${p(ro, a1)} ${p(ro - c, a1)}`,
      'Z'
    ].join('');
  }

  function arcPath(r, a1, a2, corner, sweepFlag) {
    const innerArc = r * Math.abs(a2 - a1);
    const c = Math.max(0, Math.min(corner, innerArc / 2));
    const inset = c / r;
    const s = a1 + (a2 > a1 ? inset : -inset);
    const e = a2 - (a2 > a1 ? inset : -inset);
    const [x1, y1] = pt(r, s);
    const [x2, y2] = pt(r, e);
    return `M${f3(x1)} ${f3(y1)}A${f3(r)} ${f3(r)} 0 0 ${sweepFlag} ${f3(x2)} ${f3(y2)}`;
  }

  function wrapLabel(text, maxWidth, font) {
    const maxChars = Math.max(5, Math.floor(maxWidth / (font * 0.56)));
    if (text.length <= maxChars) return [text];
    const cut = text.lastIndexOf(' ', maxChars);
    const head = (cut > 3 ? text.slice(0, cut) : text.slice(0, maxChars)).trim();
    let tail = (cut > 3 ? text.slice(cut) : text.slice(maxChars)).trim();
    if (tail.length > maxChars) tail = tail.slice(0, Math.max(3, maxChars - 1)).trimEnd() + '…';
    return [head, tail];
  }

  // Recency order: item 0 hugs the hub. Popular Mac apps and sites, not a personal desk.
  const DEFAULT_ITEMS = [
    { domain: 'github.com', label: 'PR #2140', meta: 'github.com · 2 of 4', title: 'feat: session store · Pull Request #2140', sub: 'Another desktop · 2m', fill: '#d6eaf4', badge: 'chrome' },
    { src: '/img/logos/slack.png', label: 'Slack', meta: 'slack.com', title: '#eng-oncall · 6 new', sub: 'Desktop', fill: '#d4e4f8' },
    { src: '/img/logos/cursor.png', label: 'Cursor', meta: 'Cursor', title: 'app.ts — agents', sub: 'Desktop', fill: '#ececee' },
    { domain: 'figma.com', label: 'Figma', meta: 'figma.com', title: 'Q3 launch — design file', sub: 'Desktop', fill: '#d9e4f8' },
    { icon: 'finder', label: 'Finder', meta: 'Finder', title: 'Downloads', sub: 'Desktop', fill: '#d4f3ee' },
    { src: '/img/logos/claude.png', label: 'Claude', meta: 'claude.ai', title: 'Claude', sub: 'Desktop', fill: '#f6d8cc' },
    { src: '/img/logos/chatgpt.png', label: 'ChatGPT', meta: 'chatgpt.com', title: 'ChatGPT', sub: 'Desktop', fill: '#ececea' },
    { src: '/img/logos/notes.png', label: 'Notes', meta: 'Notes', title: 'shipping checklist', sub: 'Desktop', fill: '#f6f0c8' },
    { src: '/img/logos/arc.svg', label: 'Arc', meta: 'developer.apple.com', title: 'Human Interface Guidelines', sub: 'Desktop', fill: '#e4e0f6' },
    { domain: 'notion.so', label: 'Notion', meta: 'notion.so', title: 'Weekly planning', sub: 'Desktop', fill: '#eeeee8' },
    { domain: 'warp.dev', label: 'Warp', meta: 'Warp', title: 'zsh — deploy us-east-1', sub: 'Desktop', fill: '#c8e6f0' },
    { icon: 'preview', label: 'Preview', meta: 'Preview', title: 'Screenshot 2026-08-28', sub: 'Desktop', fill: '#d0eef2' },
    { domain: 'linear.app', label: 'Linear', meta: 'linear.app', title: 'ENG-1842 · search latency', sub: 'Desktop', fill: '#e4dcf6' },
    { src: '/img/logos/music.png', label: 'Music', meta: 'Music', title: 'Discover Weekly', sub: 'Desktop', fill: '#f5dce4' },
    { domain: 'zoom.us', label: 'Zoom', meta: 'zoom.us', title: 'Standup', sub: 'Desktop', fill: '#d4e8f8' },
    { domain: 'spotify.com', label: 'Spotify', meta: 'spotify.com', title: 'Focus mix', sub: 'Desktop', fill: '#d4f0dc' }
  ];

  const BADGE_SRC = {
    chrome: '/img/logos/chrome.png',
    brave: '/img/logos/brave.png'
  };

  const ACTION = { fill: '#f4f3f1', sel: '#ececea' };
  const SCENES = {
    'desk': {
      speed: 0,
      noHint: true,
      select: 1,
      items: DEFAULT_ITEMS
    },
    'tab-search': {
      query: 'youtube',
      select: 0,
      speed: 0,
      noHint: true,
      spin: 20,
      items: [
        { domain: 'youtube.com', label: 'YouTube', meta: 'youtube.com', title: 'Fireship — JavaScript in 100 Seconds', fill: '#f3c4d0', sel: '#f3c4d0', glow: '#f4a3b8', badge: 'chrome' },
        { icon: 'search', label: 'Search the web', meta: 'Search the web', title: 'youtube', fill: ACTION.fill, sel: '#c5e4f8' },
        { icon: 'open', label: 'Open first result', meta: 'Open first result', title: 'youtube', fill: ACTION.fill, sel: '#c5e4f8' },
        { src: '/img/logos/chatgpt.png', label: 'Prompt on ChatGPT', meta: 'Prompt on ChatGPT', title: 'youtube', fill: ACTION.fill },
        { src: '/img/logos/claude.png', label: 'Prompt on Claude', meta: 'Prompt on Claude', title: 'youtube', fill: ACTION.fill },
        { icon: 'grok', label: 'Prompt on Grok', meta: 'Prompt on Grok', title: 'youtube', fill: ACTION.fill }
      ]
    },
    'web-search': {
      query: 'how to code in java',
      select: 0,
      speed: 0,
      noHint: true,
      spin: 18,
      items: [
        { icon: 'search', label: 'Search the web', meta: 'Search the web', title: 'how to code in java', fill: '#d7eef8', sel: '#c5e4f8', glow: '#8ec8e4' },
        { icon: 'open', label: 'Open first result', meta: 'Open first result', title: 'how to code in java', fill: ACTION.fill, sel: '#c5e4f8' },
        { src: '/img/logos/chatgpt.png', label: 'Prompt on ChatGPT', meta: 'Prompt on ChatGPT', title: 'how to code in java', fill: ACTION.fill },
        { src: '/img/logos/claude.png', label: 'Prompt on Claude', meta: 'Prompt on Claude', title: 'how to code in java', fill: ACTION.fill },
        { icon: 'grok', label: 'Prompt on Grok', meta: 'Prompt on Grok', title: 'how to code in java', fill: ACTION.fill }
      ]
    },
    'card-menu': {
      select: 0,
      speed: 0,
      noHint: true,
      spin: 52,
      items: [
        { domain: 'github.com', label: 'PR #2140', meta: 'github.com · 2 of 4', title: 'feat: session store · Pull Request #2140', sub: 'Another desktop · 2m', fill: '#c5e8df', sel: '#c5e8df', glow: '#7ee8d0', badge: 'chrome' },
        { src: '/img/logos/slack.png', label: 'Slack', meta: 'slack.com', title: '#eng-oncall · 6 new', sub: 'Desktop', fill: '#d4e4f8' },
        { src: '/img/logos/cursor.png', label: 'Cursor', meta: 'Cursor', title: 'app.ts — agents', sub: 'Desktop', fill: '#ececee' },
        { domain: 'figma.com', label: 'Figma', meta: 'figma.com', title: 'Q3 launch', sub: 'Desktop', fill: '#d9e4f8' },
        { icon: 'finder', label: 'Finder', meta: 'Finder', title: 'Downloads', sub: 'Desktop', fill: '#d4f3ee' },
        { icon: 'comet', label: 'Comet', meta: 'Comet', title: 'Comet', sub: 'Desktop', fill: '#e4eaf8' },
        { src: '/img/logos/notes.png', label: 'Notes', meta: 'Notes', title: 'shipping checklist', sub: 'Desktop', fill: '#f6f0c8' },
        { domain: 'linear.app', label: 'Linear', meta: 'linear.app', title: 'ENG-1842', sub: 'Desktop', fill: '#e4dcf6' }
      ]
    }
  };

  const SYMBOL_ICONS = new Set(['finder', 'preview', 'comet', 'hermes', 'search', 'open', 'grok']);

  class VortexSpiral extends HTMLElement {
    constructor() {
      super();
      this.attachShadow({ mode: 'open' });
      this._angle = 0;
      this._vel = 0;
      this._active = -1;
      this._raf = null;
      this._last = 0;
      this._entranceT = null;
      this._typeTimer = 0;
      this._hold = false;
      this._glow = MINT;
      this._reduced = matchMedia('(prefers-reduced-motion: reduce)').matches;
    }

    connectedCallback() {
      const scene = SCENES[this.getAttribute('scene')] || null;
      let items = scene ? scene.items : DEFAULT_ITEMS;
      try {
        if (this.getAttribute('items')) items = JSON.parse(this.getAttribute('items'));
      } catch (e) { /* keep defaults */ }
      this._items = items;
      this._query = this.getAttribute('query') || (scene && scene.query) || '';
      this._noHint = this.hasAttribute('nohint') || !!(scene && scene.noHint);
      if (this.hasAttribute('static')) this._speed = 0;
      else if (this.getAttribute('speed') != null) this._speed = parseFloat(this.getAttribute('speed'));
      else if (scene && scene.speed != null) this._speed = scene.speed;
      else this._speed = 2.4;
      this._angle = (scene && scene.spin) || 0;
      const selectAttr = this.getAttribute('select');
      this._prefer = selectAttr != null
        ? +selectAttr
        : (scene && scene.select != null ? scene.select : Math.min(1, Math.max(0, items.length > 1 ? 1 : 0)));
      if (this._query) this.setAttribute('search', '');
      if (this._speed === 0) this.setAttribute('still', '');
      this._build();
      this._setActive(Math.min(this._prefer, items.length - 1), false);
      if (this.hasAttribute('demo')) {
        this._speed = 0;
        this._noHint = true;
        this._applyEntrance(0);
        this.style.opacity = '0';
        this.style.pointerEvents = 'none';
        return;
      }
      const io = new IntersectionObserver((es) => {
        if (es.some((e) => e.isIntersecting)) { this._enter(); io.disconnect(); }
      }, { threshold: 0.08, rootMargin: '0px 0px 18% 0px' });
      io.observe(this);
    }

    disconnectedCallback() {
      cancelAnimationFrame(this._raf);
      clearTimeout(this._typeTimer);
    }

    _build() {
      const items = this._items;
      const N = items.length;
      const seats = Array.from({ length: N }, (_, i) => seatOf(i));
      this._geo = seats;
      this._aim = (seats[Math.min(this._prefer, N - 1)] || seats[0]).midA * R2D + this._angle;

      const outerMost = seats[N - 1].outer;
      const half = outerMost + PADDING;
      this._half = half;
      const panel = half * 2;
      const hubPct = ((HUB_RADIUS * 2) / panel) * 100;
      const wellPct = (((HUB_RADIUS - RING_INSET - 10) * 2) / panel) * 100;

      const box = contentSize();
      const nameH = TITLE_PX * 2 + 4;
      const iconSide = Math.min(ARTWORK, Math.max(24, box.height - nameH - 1));

      let defs = `
        <filter id="vx-glow" x="-80%" y="-80%" width="260%" height="260%">
          <feGaussianBlur stdDeviation="2.4" result="b"/>
          <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
        </filter>
        <filter id="vx-ring" x="-50%" y="-50%" width="200%" height="200%">
          <feGaussianBlur in="SourceGraphic" stdDeviation="1.1" result="b"/>
          <feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge>
        </filter>
        <linearGradient id="vx-preview-g" x1="18" y1="14" x2="46" y2="50" gradientUnits="userSpaceOnUse">
          <stop stop-color="#7ae0ff"/><stop offset=".35" stop-color="#7b5cff"/>
          <stop offset=".7" stop-color="#ff5ad5"/><stop offset="1" stop-color="#ffb24a"/>
        </linearGradient>
        <symbol id="vx-finder" viewBox="0 0 64 64">
          <rect width="64" height="64" rx="14" fill="#ececf1"/>
          <path d="M6 10h26v44H14a8 8 0 0 1-8-8V10z" fill="#c8c8d0"/>
          <path d="M32 10h26v36a8 8 0 0 1-8 8H32V10z" fill="#32b5e8"/>
          <path d="M20 42c5 9 19 9 24 0" fill="none" stroke="#1c1c1e" stroke-width="2.4" stroke-linecap="round"/>
          <circle cx="23" cy="30" r="2.3" fill="#1c1c1e"/>
          <circle cx="43" cy="30" r="2.3" fill="#1c1c1e"/>
        </symbol>
        <symbol id="vx-preview" viewBox="0 0 64 64">
          <rect width="64" height="64" rx="14" fill="#f4f5f7"/>
          <circle cx="32" cy="32" r="18" fill="url(#vx-preview-g)"/>
          <circle cx="32" cy="32" r="7.5" fill="#1c1c1e"/>
          <circle cx="32" cy="32" r="3.2" fill="#f4f5f7"/>
        </symbol>
        <symbol id="vx-comet" viewBox="0 0 64 64">
          <rect width="64" height="64" rx="14" fill="#edf2ff"/>
          <path d="M18 40c8-16 20-22 30-24" fill="none" stroke="#2f6bff" stroke-width="7" stroke-linecap="round"/>
          <circle cx="22" cy="44" r="10" fill="#111"/>
          <circle cx="22" cy="44" r="4.5" fill="#edf2ff"/>
        </symbol>
        <symbol id="vx-hermes" viewBox="0 0 64 64">
          <rect width="64" height="64" rx="14" fill="#ecece8"/>
          <circle cx="32" cy="24" r="10" fill="#3a3a38"/>
          <path d="M14 56c2-12 10-18 18-18s16 6 18 18" fill="#3a3a38"/>
        </symbol>
        <symbol id="vx-search" viewBox="0 0 64 64">
          <circle cx="29" cy="29" r="13.5" fill="none" stroke="#1c1c1e" stroke-width="3.6"/>
          <path d="M39 39l14 14" fill="none" stroke="#1c1c1e" stroke-width="3.6" stroke-linecap="round"/>
        </symbol>
        <symbol id="vx-open" viewBox="0 0 64 64">
          <rect x="12" y="12" width="40" height="40" rx="9" fill="none" stroke="#1c1c1e" stroke-width="3.2"/>
          <path d="M28 24h12v12M26 38l14-14" fill="none" stroke="#1c1c1e" stroke-width="3.2" stroke-linecap="round" stroke-linejoin="round"/>
        </symbol>
        <symbol id="vx-grok" viewBox="0 0 64 64">
          <rect width="64" height="64" rx="12" fill="#111"/>
          <path d="M18 44c10-22 26-28 32-16" fill="none" stroke="#f3f3f3" stroke-width="5" stroke-linecap="round"/>
          <ellipse cx="30" cy="34" rx="11" ry="13" transform="rotate(-34 30 34)" fill="none" stroke="#f3f3f3" stroke-width="4"/>
        </symbol>`;

      const wedges = [];
      for (let k = 0; k < N; k++) {
        const it = items[k];
        const s = seats[k];
        const d = wedgePath(s.inner, s.outer, s.start, s.end, CORNER);
        const innerHL = arcPath(s.inner + 2, s.start, s.end, CORNER, 1);
        const outerHL = arcPath(s.outer - 1.6, s.end, s.start, CORNER, 1);

        defs += `<radialGradient id="vxg${k}" gradientUnits="userSpaceOnUse" cx="0" cy="0" r="${f3(s.outer)}" fr="${f3(s.inner)}">
          <stop offset="0" stop-color="#fff" stop-opacity=".42"/>
          <stop offset=".12" stop-color="#fff" stop-opacity=".16"/>
          <stop offset=".38" stop-color="#fff" stop-opacity=".05"/>
          <stop offset=".68" stop-color="#fff" stop-opacity=".04"/>
          <stop offset="1" stop-color="#fff" stop-opacity=".18"/>
        </radialGradient>`;

        const ic = iconSide;
        const icX = s.cx - ic / 2;
        const icY = s.cy - box.height / 2 + 2;
        const lines = wrapLabel(it.label, box.width - 6, TITLE_PX);
        const lblY = icY + ic + 3.5 + TITLE_PX;
        const rx = ic * 0.22;

        let iconEl;
        if (SYMBOL_ICONS.has(it.icon)) {
          iconEl = `<use href="#vx-${it.icon}" x="${f3(icX)}" y="${f3(icY)}" width="${f3(ic)}" height="${f3(ic)}"/>`;
        } else {
          const href = it.src || (it.domain ? fav(it.domain) : '');
          const letter = (it.label || '?')[0].toUpperCase();
          iconEl = `
            <rect class="ico-plate" x="${f3(icX)}" y="${f3(icY)}" width="${f3(ic)}" height="${f3(ic)}" rx="${f3(rx)}" fill="#fff"/>
            <text x="${f3(s.cx)}" y="${f3(icY + ic / 2)}" font-size="${f3(ic * 0.46)}" fill="${it.fill || '#98a0ad'}" font-weight="700" text-anchor="middle" dominant-baseline="central">${esc(letter)}</text>
            ${href ? `<image class="ico" href="${esc(href)}" x="${f3(icX)}" y="${f3(icY)}" width="${f3(ic)}" height="${f3(ic)}" clip-path="url(#vxc${k})" preserveAspectRatio="xMidYMid slice"/>` : ''}`;
          defs += `<clipPath id="vxc${k}"><rect x="${f3(icX)}" y="${f3(icY)}" width="${f3(ic)}" height="${f3(ic)}" rx="${f3(rx)}"/></clipPath>`;
          if (it.badge && BADGE_SRC[it.badge]) {
            const b = ic * 0.5;
            const bx = icX - b * 0.12;
            const by = icY + ic - b * 0.72;
            iconEl += `<circle cx="${f3(bx + b / 2)}" cy="${f3(by + b / 2)}" r="${f3(b / 2 + 1.1)}" fill="#fff"/>
            <image href="${BADGE_SRC[it.badge]}" x="${f3(bx)}" y="${f3(by)}" width="${f3(b)}" height="${f3(b)}" preserveAspectRatio="xMidYMid slice"/>`;
          }
        }

        const closeA = s.end - 0.16;
        const closeR = s.inner + 16;
        const [clx, cly] = pt(closeR, closeA);
        s.clx = clx; s.cly = cly;

        const t1 = `<text class="lbl" x="${f3(s.cx)}" y="${f3(lblY)}" font-size="${TITLE_PX}">${esc(lines[0])}</text>`;
        const t2 = lines[1]
          ? `<text class="lbl" x="${f3(s.cx)}" y="${f3(lblY + TITLE_PX + 2)}" font-size="${TITLE_PX}">${esc(lines[1])}</text>`
          : '';

        wedges.push(`
      <g class="wedge" data-i="${k}" style="--fill:${it.fill || '#ececec'};--sel:${it.sel || SEL_FILL}">
        <path class="card" d="${d}"/>
        <path class="sel" d="${d}"/>
        <path class="glass" d="${d}" fill="url(#vxg${k})"/>
        <path class="rim-in" d="${innerHL}"/>
        <path class="rim-out" d="${outerHL}"/>
        <g class="content" data-i="${k}">
          <g class="ico-wrap">${iconEl}</g>
          ${t1}${t2}
        </g>
        <g class="close upright" data-i="${k}" data-cx="${f3(clx)}" data-cy="${f3(cly)}" transform="translate(${f3(clx)} ${f3(cly)})">
          <circle r="7.4" fill="rgba(32,30,29,.22)"/>
          <path d="M-2.5-2.5l5 5M2.5-2.5l-5 5" stroke="#fff" stroke-width="1.5" stroke-linecap="round"/>
        </g>
      </g>`);
      }

      // Outer turn draws on top, matching OverlayLayout hit-testing.
      const wedgeMarkup = wedges.join('');

      this.shadowRoot.innerHTML = `
<style>
  :host {
    display: block; position: relative; aspect-ratio: 1/1; width: 100%;
    container-type: inline-size;
    font-family: -apple-system, "SF Pro Text", system-ui, "Segoe UI", Roboto, sans-serif;
    -webkit-user-select: none; user-select: none; touch-action: pan-y; outline: none;
    overflow: visible;
  }
  :host(:focus-visible) .ring { box-shadow: 0 0 0 3px rgba(47,181,134,.35), 0 0 22px 6px rgba(47,181,134,.4); }
  .stage { position: absolute; inset: 0; overflow: visible; }
  .stage > svg { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; display: block; }
  .wedge { cursor: pointer; isolation: isolate; }
  .wedge .card {
    fill: var(--fill);
    stroke: rgba(255,255,255,.35);
    stroke-width: .8;
    filter: drop-shadow(0 12px 20px rgba(32,30,29,.26)) drop-shadow(0 2px 4px rgba(32,30,29,.10));
    transition: fill .22s ease;
  }
  .wedge .sel { fill: var(--sel, ${SEL_FILL}); opacity: 0; transition: opacity .22s ease; }
  .wedge .glass { pointer-events: none; opacity: .85; mix-blend-mode: soft-light; }
  .wedge .rim-in {
    fill: none; stroke: rgba(255,255,255,.88); stroke-width: 3.6;
    filter: blur(1.15px); pointer-events: none;
  }
  .wedge .rim-out {
    fill: none; stroke: rgba(255,255,255,.55); stroke-width: 2.8;
    filter: blur(.7px); pointer-events: none;
  }
  .wedge .lbl {
    text-anchor: middle; fill: #201e1d; font-weight: 510;
    paint-order: stroke; stroke: rgba(255,255,255,.45); stroke-width: .45px;
  }
  .wedge .close { display: none; }
  .wedge.on .card { filter: drop-shadow(0 14px 24px rgba(32,30,29,.30)) drop-shadow(0 2px 5px rgba(32,30,29,.12)); }
  .wedge.on .sel { opacity: 1; }
  .wedge.on .rim-in { stroke: rgba(190,255,236,.9); stroke-width: 5.5; filter: blur(1.8px); }
  .wedge.on .close { display: block; }
  .wedge.on .ico-wrap { transform-box: fill-box; transform-origin: center; transform: scale(1.12); }
  .coupling { pointer-events: none; }
  .coupling path {
    fill: none; stroke: var(--glow, ${MINT}); stroke-width: 12; stroke-linecap: round; opacity: .45;
    filter: url(#vx-glow);
  }

  .halo {
    position: absolute; left: 50%; top: 50%; width: ${f3(hubPct + 2.2)}%; aspect-ratio: 1;
    transform: translate(-50%,-50%); border-radius: 50%; pointer-events: none; z-index: 0;
    background: radial-gradient(circle,
      rgba(255,255,255,.0) 42%,
      rgba(210,255,246,.22) 62%,
      rgba(170,235,220,.18) 78%,
      transparent 100%);
  }
  .ring { display: none; }
  .hub-ring { pointer-events: none; }
  .hub {
    position: absolute; left: 50%; top: 50%;
    width: ${f3(wellPct)}%; height: ${f3(wellPct)}%;
    transform: translate(-50%,-50%); border-radius: 50%;
    background: rgba(255,255,255,.16);
    backdrop-filter: blur(20px) saturate(1.2);
    -webkit-backdrop-filter: blur(20px) saturate(1.2);
    box-shadow: inset 0 0 20px 6px rgba(220,255,248,.18);
    display: flex; flex-direction: column; align-items: center; justify-content: center;
    text-align: center; padding: 0; box-sizing: border-box; overflow: hidden;
    pointer-events: none; z-index: 3;
    font-size: clamp(10px, 2.6cqi, 14px);
  }
  .hub .k, .hub .t, .hub .s { max-width: 68%; min-width: 0; }
  .hub .k {
    font-size: .62em; color: rgba(32,30,29,.62); margin-bottom: .28em; font-weight: 500;
    overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    text-shadow: 0 1px 6px rgba(255,255,255,.75);
  }
  .hub .t {
    font-weight: 700; color: #201e1d; font-size: 1em; line-height: 1.18;
    display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical;
    overflow: hidden; overflow-wrap: anywhere;
    text-shadow: 0 1px 8px rgba(255,255,255,.8);
  }
  .hub .s {
    font-size: .62em; color: rgba(32,30,29,.58); margin-top: .32em; white-space: nowrap;
    overflow: hidden; text-overflow: ellipsis;
    text-shadow: 0 1px 6px rgba(255,255,255,.75);
  }
  .hub.pulse { animation: vxpulse .45s ease; }
  @keyframes vxpulse {
    0% { transform: translate(-50%,-50%) scale(1); }
    40% { transform: translate(-50%,-50%) scale(1.045); }
    100% { transform: translate(-50%,-50%) scale(1); }
  }
  .hint {
    position: absolute; left: 50%; bottom: -2.1em; transform: translateX(-50%);
    font-size: clamp(10px, 2.3cqi, 12.5px); color: rgba(32,30,29,.48); white-space: nowrap;
  }
  .hint b { color: rgba(32,30,29,.72); font-weight: 600; }
  :host([search]) .hint, :host([search]) .wedge .close,
  :host([still]) .hint, :host([still]) .wedge .close { display: none !important; }
  :host([search]) { --lift: 11%; }
  :host([search]) .stage > svg { top: calc(-1 * var(--lift)); bottom: var(--lift); }
  :host([search]) .hub,
  :host([search]) .halo { top: calc(50% - var(--lift)); }
  .qpill {
    position: absolute; left: 50%; top: 5.5%;
    transform: translateX(-50%);
    z-index: 6; pointer-events: none;
    display: none; align-items: center; gap: 7px;
    background: #fff; color: #201e1d;
    border-radius: 999px; padding: 8px 14px 8px 11px;
    box-shadow: 0 10px 28px rgba(32,30,29,.18), 0 1px 0 rgba(255,255,255,.8);
    font-size: clamp(13px, 3.6cqi, 17px); font-weight: 560;
    letter-spacing: -0.018em; white-space: nowrap; line-height: 1;
  }
  :host([search]) .qpill { display: flex; top: 3.6%; }
  :host([search]) .hub .k { display: block; }
  .qpill svg {
    position: static;
    inset: auto;
    display: block;
    width: 14px; height: 14px;
    flex: none;
    overflow: visible;
  }
  .qtext { display: block; line-height: 1; }
  .qcaret {
    width: 1.5px; height: 0.95em; background: #007aff; border-radius: 1px;
    align-self: center;
    animation: vxc 1s steps(1) infinite;
  }
  .qcaret.idle { animation: vxc 1.1s steps(1) infinite; }
  @keyframes vxc { 50% { opacity: 0; } }
  @media (hover: none) { .hint .m1 { display: none; } }
  @media (hover: hover) { .hint .m2 { display: none; } }
  @container (max-width: 520px) {
    .hub { font-size: clamp(9px, 2.8cqi, 12px); }
    .hub .k, .hub .s { display: none; }
    .hub .t { -webkit-line-clamp: 2; font-size: 1em; max-width: 70%; }
  }
</style>
<div class="stage" part="stage">
  <div class="halo"></div>
  <svg viewBox="-${f3(half)} -${f3(half)} ${f3(panel)} ${f3(panel)}" aria-hidden="true">
    <defs>${defs}</defs>
    <g class="orbit">${wedgeMarkup}<g class="coupling"><path d=""/></g></g>
    <circle class="hub-ring" r="${f3(HUB_RADIUS - RING_INSET)}" fill="none" stroke="#c8fff4" stroke-width="9" opacity=".4" filter="url(#vx-glow)"/>
    <circle class="hub-ring" r="${f3(HUB_RADIUS - RING_INSET)}" fill="none" stroke="#f4fffe" stroke-width="1.7" opacity=".95" filter="url(#vx-ring)"/>
  </svg>
  <div class="ring"></div>
  <div class="hub">
    <div class="k">—</div>
    <div class="t">—</div>
    <div class="s">—</div>
  </div>
  <div class="qpill" aria-hidden="true">
    <svg viewBox="0 0 16 16" fill="none" stroke="#201e1d" stroke-width="1.55" stroke-linecap="round" aria-hidden="true"><circle cx="6.7" cy="6.7" r="4.35"/><path d="M10 10.1L14.15 14.2"/></svg>
    <span class="qtext"></span>
    <span class="qcaret"></span>
  </div>
  ${this._noHint ? '' : '<div class="hint"><span class="m1"><b>Hover</b> to peek · <b>click</b> to switch</span><span class="m2"><b>Tap</b> to switch</span></div>'}
</div>
<span class="sr" role="status" aria-live="polite" style="position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0)"></span>`;

      this.shadowRoot.querySelectorAll('image').forEach((im) =>
        im.addEventListener('error', () => im.remove(), { once: true }));
      this._orbit = this.shadowRoot.querySelector('.orbit');
      this._wedgeEls = [...this.shadowRoot.querySelectorAll('.wedge')];
      this._contentEls = [...this.shadowRoot.querySelectorAll('.content')];
      this._uprightEls = [...this.shadowRoot.querySelectorAll('.upright')];
      this._hub = this.shadowRoot.querySelector('.hub');
      this._hubK = this.shadowRoot.querySelector('.hub .k');
      this._hubT = this.shadowRoot.querySelector('.hub .t');
      this._hubS = this.shadowRoot.querySelector('.hub .s');
      this._coupling = this.shadowRoot.querySelector('.coupling path');
      this._qtext = this.shadowRoot.querySelector('.qtext');
      this._qcaret = this.shadowRoot.querySelector('.qcaret');
      this._sr = this.shadowRoot.querySelector('.sr');
      if (this._query) {
        this._hold = true;
        this._entranceT = 0;
        this._applyEntrance(0);
      }

      this.setAttribute('role', 'application');
      this.setAttribute('tabindex', '0');
      this.setAttribute('aria-label', this._query
        ? `VortexFlow search overlay for ${this._query}`
        : 'VortexFlow spiral. Arrow keys move between windows, Enter switches.');

      this._bind();
      if (this._reduced) { this._entranceT = 1; this._applyEntrance(1); }
      this._vel = this._reduced ? 0 : this._speed;
      if (!this._tickBound) {
        this._tick = this._tick.bind(this);
        this._tickBound = true;
      }
      this._last = performance.now();
      cancelAnimationFrame(this._raf);
      this._raf = requestAnimationFrame(this._tick);
      this._drawCoupling();
    }

    playScene(name) {
      const scene = SCENES[name];
      if (!scene) return Promise.resolve();
      const prevTyped = (this._qtext && this._qtext.textContent) || '';
      cancelAnimationFrame(this._raf);
      clearTimeout(this._typeTimer);
      this._items = scene.items || DEFAULT_ITEMS;
      this._query = scene.query || '';
      this._noHint = true;
      this._speed = 0;
      this._angle = scene.spin || 0;
      this._prefer = scene.select != null ? scene.select : 0;
      this._active = -1;
      this._entranceT = 0;
      this.toggleAttribute('search', !!this._query);
      this.setAttribute('still', '');
      this._build();
      if (this._qtext && prevTyped) this._qtext.textContent = prevTyped;
      this._setActive(Math.min(this._prefer, this._items.length - 1), false);
      this._applyEntrance(0);
      this._hold = false;
      this._enter();
      const typeMs = this._query
        ? 280 + this._query.length * 58 + (prevTyped && prevTyped !== this._query ? prevTyped.length * 26 : 0) + 1000
        : 1200;
      return new Promise((res) => { setTimeout(res, typeMs); });
    }

    hideSpiral() {
      this.classList.remove('is-shown');
      this.style.opacity = '0';
    }

    showSpiral() {
      this.classList.add('is-shown');
      this.style.opacity = '1';
      this.style.pointerEvents = 'none';
    }

    _bind() {
      const stage = this.shadowRoot.querySelector('.stage');
      this._wedgeEls.forEach((w) => {
        const i = +w.dataset.i;
        w.addEventListener('pointerenter', () => this._setActive(i));
        w.addEventListener('click', () => this._switch(i));
      });
      if (this._hostBound) return;
      this._hostBound = true;
      stage.addEventListener('pointerenter', () => { this._inside = true; });
      stage.addEventListener('pointerleave', () => { this._inside = false; });

      if (this._speed) {
        this.addEventListener('wheel', (e) => {
          e.preventDefault();
          const d = Math.max(-40, Math.min(40, e.deltaY));
          this._angle += d * 0.32;
          this._snapActiveToAim();
        }, { passive: false });

        let dragging = false, lastA = 0;
        const angAt = (e) => {
          const r = stage.getBoundingClientRect();
          return Math.atan2(e.clientY - (r.top + r.height / 2), e.clientX - (r.left + r.width / 2)) / D2R;
        };
        stage.addEventListener('pointerdown', (e) => {
          dragging = true; lastA = angAt(e); this._dragMoved = 0;
        });
        addEventListener('pointermove', (e) => {
          if (!dragging) return;
          const a = angAt(e); let d = a - lastA;
          if (d > 180) d -= 360; if (d < -180) d += 360;
          this._angle += d; this._dragMoved += Math.abs(d); lastA = a;
          if (this._dragMoved > 2) this._snapActiveToAim();
        });
        addEventListener('pointerup', () => { dragging = false; });
      }

      this.addEventListener('keydown', (e) => {
        if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { this._step(1); e.preventDefault(); }
        else if (e.key === 'ArrowLeft' || e.key === 'ArrowUp') { this._step(-1); e.preventDefault(); }
        else if (e.key === 'Enter' || e.key === ' ') {
          if (this._active >= 0) this._switch(this._active);
          e.preventDefault();
        }
      });
    }

    _worldMid(i) {
      let m = (this._geo[i].midA * R2D + this._angle) % 360;
      if (m > 180) m -= 360; if (m < -180) m += 360;
      return m;
    }

    _snapActiveToAim() {
      let best = -1, bd = 1e9;
      for (let i = 0; i < this._items.length; i++) {
        let d = Math.abs(this._worldMid(i) - this._aim);
        if (d > 180) d = 360 - d;
        d += i * 0.12;
        if (d < bd) { bd = d; best = i; }
      }
      if (best !== this._active) this._setActive(best);
    }

    _step(dir) {
      const n = this._items.length;
      this._setActive(((this._active < 0 ? 0 : this._active) + dir + n) % n);
    }

    _setActive(i, announce = true) {
      if (i < 0 || i === this._active) return;
      this._active = i;
      const it = this._items[i];
      this._wedgeEls.forEach((w) => {
        const on = +w.dataset.i === i;
        w.classList.toggle('on', on);
      });
      this._hubK.textContent = it.meta || '';
      this._hubT.textContent = (it.title || it.label).replace(/…$/, '');
      this._hubS.textContent = it.sub || '';
      this._hubK.style.display = this._hubK.textContent ? '' : 'none';
      this._hubS.style.display = this._hubS.textContent ? '' : 'none';
      this._glow = it.glow || MINT;
      if (this._coupling) this._coupling.parentElement.style.setProperty('--glow', this._glow);
      this._drawCoupling();
      if (announce && this._sr) this._sr.textContent = `${it.label}${it.sub ? ', ' + it.sub : ''}`;
    }

    _drawCoupling() {
      if (!this._coupling || this._active < 0) return;
      const s = this._geo[this._active];
      this._coupling.setAttribute('d', arcPath(s.inner - 4, s.start + 0.08, s.end - 0.08, 8, 1));
    }

    _switch(i) {
      this._setActive(i);
      const it = this._items[i];
      this._hub.classList.remove('pulse');
      void this._hub.offsetWidth;
      this._hub.classList.add('pulse');
      this.dispatchEvent(new CustomEvent('vortex-switch', { detail: it, bubbles: true }));
    }

    _enter() {
      if (this._reduced) {
        this._hold = false;
        this._entranceT = 1;
        this._applyEntrance(1);
        if (this._qtext && this._query) this._qtext.textContent = this._query;
        if (this._qcaret) this._qcaret.classList.add('idle');
        return;
      }
      this._hold = false;
      this._entranceT = 0;
      if (this._query) this._typeQuery(this._query);
    }

    _typeQuery(text, done) {
      if (!this._qtext) { if (done) done(); return; }
      if (this._qcaret) this._qcaret.classList.remove('idle');
      const start = this._qtext.textContent || '';
      const run = (from) => {
        let i = from;
        if (i > 0 && start && from === start.length) {
          const del = () => {
            i -= 1;
            this._qtext.textContent = start.slice(0, Math.max(0, i));
            if (i > 0) this._typeTimer = setTimeout(del, 22);
            else this._typeTimer = setTimeout(() => run(0), 80);
          };
          del();
          return;
        }
        i = 0;
        const step = () => {
          i += 1;
          this._qtext.textContent = text.slice(0, i);
          if (i < text.length) {
            this._typeTimer = setTimeout(step, 38 + Math.random() * 36);
          } else {
            if (this._qcaret) this._qcaret.classList.add('idle');
            this._typeTimer = setTimeout(() => { if (done) done(); }, 120);
          }
        };
        this._typeTimer = setTimeout(step, from ? 40 : 180);
      };
      if (start && start !== text) run(start.length);
      else {
        this._qtext.textContent = '';
        run(0);
      }
    }

    _applyEntrance(t) {
      this._wedgeEls.forEach((w) => {
        const k = +w.dataset.i;
        const d = Math.min(1, Math.max(0, t * 1.45 - k * 0.035));
        const e = 1 - Math.pow(1 - d, 3);
        w.style.opacity = e;
        if (e < 1) {
          w.style.transform = `rotate(${(1 - e) * -28}deg)`;
          w.style.transformOrigin = '0px 0px';
        } else {
          w.style.transform = '';
          w.style.opacity = '';
        }
      });
    }

    _tick(now) {
      const dt = Math.min(0.05, (now - this._last) / 1000);
      this._last = now;

      if (!this._hold && this._entranceT !== null && this._entranceT < 1) {
        this._entranceT = Math.min(1, this._entranceT + dt * 0.9);
        this._applyEntrance(this._entranceT);
      }

      const entering = this._hold || (this._entranceT !== null && this._entranceT < 1);
      const target = (this._inside || this._reduced || entering) ? 0 : this._speed;
      this._vel += (target - this._vel) * Math.min(1, dt * 3);
      if (Math.abs(this._vel) > 0.01) {
        this._angle = (this._angle + this._vel * dt) % 360;
        if (!this._inside) this._snapActiveToAim();
      }

      this._orbit.setAttribute('transform', `rotate(${f3(this._angle)})`);
      for (const c of this._contentEls) {
        const i = +c.dataset.i, g = this._geo[i];
        c.setAttribute('transform', `rotate(${f3(-this._angle)} ${g.cx} ${g.cy})`);
      }
      for (const c of this._uprightEls) {
        const cx = +c.dataset.cx, cy = +c.dataset.cy;
        c.setAttribute('transform', `translate(${f3(cx)} ${f3(cy)}) rotate(${f3(-this._angle)})`);
      }
      this._raf = requestAnimationFrame(this._tick);
    }
  }

  if (!customElements.get('vortex-spiral')) {
    customElements.define('vortex-spiral', VortexSpiral);
  }
})();
