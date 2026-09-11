/* Timed visual storytelling. Every action stays inside this example. */
(function () {
  'use strict';
  const root = document.querySelector('.spiral-revision');
  if (!root) return;
  const $ = (selector) => root.querySelector(selector);
  const all = (selector) => [...root.querySelectorAll(selector)];
  const WINDOWS = [
    { id: 'research', src: '/img/logos/chrome.png', label: 'Chrome', title: 'Research notes', meta: 'Chrome', sub: 'Current window', fill: '#eaf6f2', body: 'Ideas worth keeping.', detail: 'Notes · References · Next steps' },
    { id: 'brief', src: '/img/logos/chrome.png', label: 'Chrome', title: 'Release brief', meta: 'Chrome', sub: 'Previous window', fill: '#e7f4e8', body: 'A little room to focus.', detail: 'Launch plan · Ready for review' },
    { id: 'slack', src: '/img/logos/slack.png', label: 'Slack', title: 'Northstar team', meta: 'Slack', sub: 'Current display', fill: '#f8e9ef', body: 'A clear next step.', detail: 'Team updates · Project Northstar' },
    { id: 'safari', src: '/img/logos/safari-native.png', label: 'Safari', title: 'Reading list', meta: 'Safari', sub: 'Another Space', fill: '#ebf2fb', body: 'A few good reads.', detail: 'Saved for later · Reference library' },
    { id: 'notes', src: '/img/logos/notes.png', label: 'Notes', title: 'Ideas for later', meta: 'Notes', sub: 'Current display', fill: '#f8f3df', body: 'Good ideas deserve a place to land.', detail: 'Thinking · Sketching · Exploring' },
    { id: 'finder', src: '/img/logos/finder-native.png', label: 'Finder', title: 'Project files', meta: 'Finder', sub: 'Current display', fill: '#e5f4f3', body: 'Everything for the project.', detail: 'Brief · Research · Assets' },
    { id: 'cursor', src: '/img/logos/cursor.png', label: 'Cursor', title: 'Workspace', meta: 'Cursor', sub: 'Current display', fill: '#f1eff2', body: 'Pick up where you left off.', detail: 'Source · Changes · Workspace' },
    { id: 'snowflake', src: '/img/logos/snowflake.png', badge: 'chrome', label: 'Snowflake', title: 'Snowflake', meta: 'app.snowflake.com', sub: 'Browser tab', fill: '#e6f5fa', sel: '#bce5f1', glow: '#b1eaff', body: 'Your analytics workspace.', detail: 'Worksheets · Projects · Results' },
    { id: 'music', src: '/img/logos/music.png', label: 'Music', title: 'Focus playlist', meta: 'Music', sub: 'Audio playing', fill: '#f7e9ee', body: 'A soundtrack for your flow.', detail: 'Focus playlist · Now playing' },
    { id: 'terminal', src: '/img/logos/terminal.png', label: 'Terminal', title: 'Local project', meta: 'Apple Terminal', sub: 'Second display', fill: '#edf4ef', body: 'Ready for your next command.', detail: 'Project Northstar · Local session' },
    { id: 'claude', src: '/img/logos/claude.png', label: 'Claude', title: 'A fresh idea', meta: 'Claude', sub: 'Current display', fill: '#f9ece5', body: 'A new perspective.', detail: 'Draft · Explore · Refine' },
    { id: 'chatgpt', src: '/img/logos/chatgpt.png', label: 'ChatGPT', title: 'Creative thinking', meta: 'ChatGPT', sub: 'Current display', fill: '#f0f0ed', body: 'Room for a good question.', detail: 'New conversation · Ideas' },
    { id: 'figma', src: '/img/logos/figma.png', label: 'Figma', title: 'Launch design', meta: 'Figma', sub: 'Another Space', fill: '#eeebf8', body: 'Make the next detail count.', detail: 'Design · Prototype · Review' },
    { id: 'linear', src: '/img/logos/linear.png', label: 'Linear', title: 'Project roadmap', meta: 'Linear', sub: 'Current display', fill: '#eeebf9', body: 'The work ahead, in order.', detail: 'Plan · Build · Ship' },
    { id: 'notion', src: '/img/logos/notion.png', label: 'Notion', title: 'Weekly planning', meta: 'Notion', sub: 'Current display', fill: '#f2f1ee', body: 'A little clarity for the week.', detail: 'Goals · Notes · Next steps' },
    { id: 'brave', src: '/img/logos/brave.png', label: 'Brave', title: 'Reference board', meta: 'Brave', sub: 'Current display', fill: '#f9e9e7', body: 'The useful things you found.', detail: 'Reading · Inspiration · References' }
  ];
  const PINS = [
    { id: 'grok', title: 'grok.com', shortLabel: 'grok.com', kind: 'Pinned link', src: '/img/logos/grok.png' },
    { id: 'pinned-cursor', title: 'Cursor', shortLabel: 'Cursor', kind: 'Pinned app', src: '/img/logos/cursor.png' },
    { id: 'keys', title: 'Find in page', shortLabel: '⌘ F', kind: 'Keyboard shortcut', label: '⌘ F' }
  ];
  const LAYOUT_WINDOWS = WINDOWS.slice(0, 8);
  const stage = $('#story-stage');
  const spiral = $('#hero-spiral');
  const pointer = $('#story-pointer');
  const receipt = $('#story-receipt');
  const play = $('#story-play');
  const reducedQuery = matchMedia('(prefers-reduced-motion: reduce)');
  let reduced = reducedQuery.matches;
  let chapter = 'windows';
  let displayedItems = WINDOWS;
  let displayedPins = [];
  let currentQuery = '';
  let signature = '';
  let elapsed = 0;
  let nextFrame = 0;
  let clockStart = 0;
  let timer = 0;
  let playing = false;
  let userPaused = false;
  let takeover = false;
  let visible = false;
  let booted = false;
  let manualSearch = false;

  function setAppearance(appearance) {
    root.dataset.appearance = appearance;
    all('vortex-spiral').forEach((widget) => widget.setAppearance(appearance));
    all('[data-appearance-choice]').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.appearanceChoice === appearance));
    });
  }
  all('[data-appearance-choice]').forEach((button) => button.addEventListener('click', () => {
    setAppearance(button.dataset.appearanceChoice);
  }));

  const chapterCopy = {
    open: ['01 / One press', 'A mouse button or a shortcut. Everything opens at the pointer.'],
    windows: ['02 / Your windows', 'Everything open. One place to choose.'],
    search: ['03 / Find a tab', 'A few letters. The right tab.'],
    web: ['04 / Search & ask', 'Keep going, even when it isn’t open.'],
    pins: ['05 / Your favorites', 'Your everyday shortcuts, in the seam.']
  };

  function setCaption(name, message) {
    chapter = name;
    stage.dataset.scene = name;
    $('#story-phase').textContent = chapterCopy[name][0];
    $('#story-caption').textContent = message || chapterCopy[name][1];
    all('[data-chapter]').forEach((button) => button.setAttribute('aria-pressed', String(button.dataset.chapter === name)));
  }

  function actions(query) {
    return [
      { id: 'search-web', icon: 'search', label: 'Search the web', title: query, meta: 'Search the web', fill: '#f5f5f2', sel: '#c1e7f2', kind: 'web' },
      { id: 'first-result', icon: 'open', label: 'Open first result', title: query, meta: 'Open first result', fill: '#f5f5f2', sel: '#c1e7f2', kind: 'web' },
      { id: 'ask-chatgpt', src: '/img/logos/chatgpt.png', label: 'Prompt on ChatGPT', title: query, meta: 'Prompt on ChatGPT', fill: '#f5f5f2', kind: 'assistant' },
      { id: 'ask-claude', src: '/img/logos/claude.png', label: 'Prompt on Claude', title: query, meta: 'Prompt on Claude', fill: '#f5f5f2', kind: 'assistant' },
      { id: 'ask-grok', src: '/img/logos/grok.png', label: 'Prompt on Grok', title: query, meta: 'Prompt on Grok', fill: '#f5f5f2', kind: 'assistant' }
    ];
  }

  function render(items, { query = '', search = false, pins = [], animate = true, selected = 1 } = {}) {
    displayedItems = items;
    displayedPins = pins;
    currentQuery = query;
    const key = items.map((item) => item.id).join('|') + ':' + pins.map((pin) => pin.id).join('|');
    receipt.hidden = true;
    if (signature !== key) {
      signature = key;
      spiral.setExample(items, { query, search, pins, showPlus: true, selected,
        animate: animate && !reduced });
    } else {
      spiral.setQueryText(query, search || Boolean(query));
      // Action titles follow every keystroke, without rebuilding an unchanged ring.
      spiral.updateExampleItems(items);
      spiral.selectExample(selected, false);
    }
  }

  function fullWindowScene(animate = true) {
    manualSearch = false;
    setCaption('windows');
    render(WINDOWS, { pins: [], animate });
  }

  function searchScene(query, animate = true) {
    currentQuery = query;
    const term = query.trim().toLowerCase();
    if (!term) {
      setCaption('windows');
      render(WINDOWS, { query: '', search: manualSearch, pins: [], animate });
      return;
    }
    let matches = WINDOWS.filter((item) => (item.title + ' ' + item.label + ' ' + item.meta).toLowerCase().includes(term));
    // A clean example of a browser tab with the site's icon over its browser icon.
    matches = matches.map((item) => item.id === 'snowflake' ? { ...item, kind: 'tab' } : item);
    if (!matches.length && 'visual studio code'.includes(term)) {
      matches = [{ id: 'installed-editor', src: '/img/logos/cursor.png', label: 'Code editor', title: 'Code editor', meta: 'Installed application', fill: '#edf1ef', kind: 'app' }];
    }
    setCaption(matches.length ? 'search' : 'web');
    render([...matches, ...actions(query)], { query, search: true, pins: [], selected: 0, animate });
  }

  function pinsScene(animate = true) {
    manualSearch = false;
    setCaption('pins');
    render(WINDOWS, { pins: PINS.slice(0, 2), animate });
    spiral.selectPin(0, false);
  }

  function hidePointer() {
    pointer.classList.remove('is-visible', 'is-clicking');
    pointer.style.transitionDuration = '0s';
  }

  // The activation beat: the overlay is closed, a mouse button or shortcut is pressed, the spiral opens.
  const trigger = $('#story-trigger');
  let triggerTimer = 0;
  function showTrigger(mode) {
    clearTimeout(triggerTimer);
    trigger.dataset.mode = mode;
    trigger.classList.remove('is-pressed', 'is-leaving', 'is-visible');
    trigger.hidden = false;
    requestAnimationFrame(() => trigger.classList.add('is-visible'));
  }
  function hideTrigger(immediate = false) {
    clearTimeout(triggerTimer);
    trigger.classList.remove('is-visible');
    if (immediate) { trigger.hidden = true; trigger.classList.remove('is-leaving', 'is-pressed'); return; }
    trigger.classList.add('is-leaving');
    triggerTimer = setTimeout(() => { trigger.hidden = true; trigger.classList.remove('is-leaving', 'is-pressed'); }, 380);
  }
  function closedScene(mode) {
    signature = '';
    fullWindowScene(false);
    setCaption('open');
    showTrigger(mode);
  }
  function openSpiral() {
    hideTrigger();
    setCaption('windows');
    spiral.playEntrance();
  }
  // Leaving the closed beat by any route (pause, chapter jump, reduced motion) must show the spiral.
  function settleOpenScene() {
    if (stage.dataset.scene !== 'open') return;
    hideTrigger(true);
    setCaption('windows');
  }

  function moveTo(index, pin = false) {
    if (reduced) return;
    const target = spiral.targetPoint(index, pin);
    if (!target) return;
    const bounds = stage.getBoundingClientRect();
    pointer.style.transitionDuration = '.75s';
    pointer.classList.add('is-visible');
    pointer.style.left = target.x - bounds.left - 5 + 'px';
    pointer.style.top = target.y - bounds.top - 3 + 'px';
  }

  function pointerClick() {
    pointer.classList.remove('is-clicking');
    void pointer.offsetWidth;
    pointer.classList.add('is-clicking');
  }

  function showReceipt(item, pin = false) {
    const title = pin
      ? (item.kind === 'Keyboard shortcut' ? 'Shortcut sent: ' : 'Opened from pins: ') + item.title
      : item.kind === 'assistant' || item.kind === 'web'
        ? item.meta + ' is ready'
        : item.kind === 'app' ? 'Launched ' + item.title : 'Brought forward: ' + item.title;
    $('#receipt-title').textContent = title;
    $('#receipt-icon').src = item.src || '/img/mark.svg?v=3';
    receipt.hidden = false;
  }

  function pause(reason = 'manual') {
    if (playing) elapsed += performance.now() - clockStart;
    playing = false;
    clearTimeout(timer);
    timer = 0;
    if (reason === 'manual' || reason === 'button' || reason === 'reduced') userPaused = true;
    if (reason === 'manual') takeover = true;
    hidePointer();
    settleOpenScene();
    spiral.stopMotion();
    if (reason === 'button') all('vortex-spiral').forEach((widget) => widget.setAmbientPaused(true));
    play.setAttribute('aria-pressed', 'false');
    play.textContent = takeover ? 'Play story' : 'Resume';
    stage.dataset.playing = 'false';
    if (reason === 'manual') {
      $('#story-instruction').textContent = 'You’re in control: pick a card, use arrow keys and Enter, or type. The story resumes on its own after a while.';
      armIdleResume();
    } else clearTimeout(idleTimer);
  }

  // After the visitor takes over, the story comes back once they have been idle for a while,
  // never while the pointer rests on the demo or the widget has keyboard focus.
  const IDLE_RESUME_MS = 30000;
  let idleTimer = 0;
  let pointerInside = false;
  function armIdleResume() {
    clearTimeout(idleTimer);
    if (!takeover) return;
    idleTimer = setTimeout(() => {
      const focused = spiral.contains(document.activeElement) || spiral.shadowRoot?.activeElement;
      if (!takeover || playing || pointerInside || focused || !visible || document.hidden || reduced) { armIdleResume(); return; }
      run(true);
    }, IDLE_RESUME_MS);
  }
  stage.addEventListener('pointerenter', () => { pointerInside = true; });
  stage.addEventListener('pointerleave', () => { pointerInside = false; armIdleResume(); });
  stage.addEventListener('pointermove', () => armIdleResume(), { passive: true });
  stage.addEventListener('keydown', () => armIdleResume());

  const frames = [];
  const at = (time, run) => frames.push({ time, run });
  function typePhrase(time, phrase) {
    at(time, () => {
      manualSearch = true;
      if (reduced) searchScene(phrase, false);
      else spiral.setQueryText('', true);
    });
    [...phrase].forEach((_, index) => at(time + 180 + index * 135, () => {
      if (!reduced) searchScene(phrase.slice(0, index + 1));
    }));
  }
  // The story loops; each pass opens the overlay a different way.
  let loops = 0;
  const OPEN = 1700;
  at(0, () => {
    hidePointer();
    pointer.style.left = '15%'; pointer.style.top = '80%';
    closedScene(loops % 2 ? 'keys' : 'mouse');
    $('#story-instruction').textContent = 'Click the spiral to take control — then pick a card, use arrow keys and Enter, or type to find it.';
  });
  at(1000, () => trigger.classList.add('is-pressed'));
  at(1450, () => openSpiral());
  at(OPEN + 1200, () => moveTo(1));
  at(OPEN + 2000, () => spiral.selectExample(1, false));
  at(OPEN + 3150, () => { pointerClick(); showReceipt(WINDOWS[1]); });
  at(OPEN + 4550, () => { receipt.hidden = true; hidePointer(); });
  typePhrase(OPEN + 4800, 'snowfl');
  at(OPEN + 6500, () => moveTo(0));
  at(OPEN + 7350, () => spiral.selectExample(0, false));
  at(OPEN + 8500, () => { pointerClick(); showReceipt(displayedItems[0]); });
  at(OPEN + 10100, () => { receipt.hidden = true; hidePointer(); });
  typePhrase(OPEN + 10400, 'how to start a project');
  at(OPEN + 13700, () => moveTo(2));
  at(OPEN + 14500, () => spiral.selectExample(2, false));
  at(OPEN + 15700, () => { pointerClick(); showReceipt(displayedItems[2]); });
  at(OPEN + 17300, () => { hidePointer(); pinsScene(); });
  at(OPEN + 18400, () => moveTo(0, true));
  at(OPEN + 19200, () => spiral.selectPin(0, false));
  at(OPEN + 20500, () => { pointerClick(); showReceipt(PINS[0], true); });
  at(OPEN + 22300, () => { receipt.hidden = true; moveTo(1, true); });
  at(OPEN + 23100, () => spiral.selectPin(1, false));
  at(OPEN + 24200, () => { pointerClick(); showReceipt(PINS[1], true); });
  at(OPEN + 26100, () => {
    hidePointer(); receipt.hidden = true;
    setCaption('pins', 'A little less hunting. A lot more flow.');
  });
  frames.sort((a, b) => a.time - b.time);
  const duration = OPEN + 28600;

  function tick() {
    if (!playing) return;
    let time = elapsed + performance.now() - clockStart;
    while (nextFrame < frames.length && frames[nextFrame].time <= time) {
      frames[nextFrame].run();
      nextFrame += 1;
    }
    stage.dataset.progress = String(Math.min(100, Math.round(time / duration * 100)));
    if (time >= duration) {
      loops += 1;
      elapsed = 0; nextFrame = 0; clockStart = performance.now(); time = 0;
    }
    timer = setTimeout(tick, 70);
  }

  function run(restart = false) {
    if (!booted || playing) return;
    clearTimeout(timer);
    clearTimeout(idleTimer);
    if (restart || takeover) {
      elapsed = 0; nextFrame = 0;
    }
    userPaused = false;
    takeover = false;
    playing = true;
    all('vortex-spiral').forEach((widget) => widget.setAmbientPaused(false));
    clockStart = performance.now();
    play.textContent = 'Pause';
    play.setAttribute('aria-pressed', 'true');
    stage.dataset.playing = 'true';
    tick();
  }

  function jump(name) {
    pause('manual');
    hideTrigger(true);
    signature = '';
    if (name === 'search') { manualSearch = true; searchScene('snowfl'); }
    else if (name === 'web') { manualSearch = true; searchScene('how to start a project'); }
    else if (name === 'pins') pinsScene();
    else fullWindowScene();
  }

  all('[data-chapter]').forEach((button) => button.addEventListener('click', () => jump(button.dataset.chapter)));
  play.addEventListener('click', () => { if (playing) pause('button'); else run(false); });
  $('#story-replay').addEventListener('click', () => { pause('button'); run(true); });
  $('#story-search').addEventListener('click', () => {
    pause('manual'); manualSearch = true; spiral.focusSearch();
  });
  // Hovering is not a decision. A click on the stage, a key, or focus is; those hand the demo over.
  spiral.addEventListener('vortex-interaction', (event) => {
    if (playing && event.detail.kind !== 'hover') pause('manual');
  });
  stage.addEventListener('click', (event) => {
    if (!playing || event.target.closest('.glass-appearance')) return;
    pause('manual');
  });
  spiral.addEventListener('vortex-query', (event) => {
    pause('manual'); manualSearch = true; searchScene(event.detail);
  });
  spiral.addEventListener('vortex-select', (event) => {
    if (!playing) $('#story-caption').textContent = event.detail.title + ' · ' + event.detail.meta;
  });
  spiral.addEventListener('vortex-pin-select', (event) => {
    if (!playing) $('#story-caption').textContent = event.detail.kind + ' · ' + event.detail.title;
  });
  spiral.addEventListener('vortex-switch', (event) => { pause('manual'); showReceipt(event.detail); });
  spiral.addEventListener('vortex-pin', (event) => { pause('manual'); showReceipt(event.detail, true); });
  spiral.addEventListener('vortex-add-pin', () => {
    pause('manual'); signature = ''; setCaption('pins', 'A keyboard shortcut, pinned right here.');
    render(WINDOWS, { pins: PINS, animate: true });
    spiral.selectPin(2);
    showReceipt(PINS[2], true);
  });

  new IntersectionObserver((entries) => {
    visible = entries.some((entry) => entry.isIntersecting);
    if (!visible && playing) pause('offscreen');
    else if (visible && booted && !userPaused && !document.hidden && !reduced) run(false);
  }, { threshold: .22 }).observe(stage);
  document.addEventListener('visibilitychange', () => {
    if (document.hidden && playing) pause('hidden');
    else if (!document.hidden && visible && !userPaused && !reduced) run(false);
  });

  function applyReduced(value) {
    reduced = value;
    root.classList.toggle('is-reduced', value);
    all('vortex-spiral').forEach((widget) => widget.setReducedMotion(value));
    $('#story-reduced').checked = value;
    if (value) pause('reduced');
  }
  reducedQuery.addEventListener('change', (event) => applyReduced(event.matches));
  $('#story-reduced').addEventListener('change', (event) => applyReduced(event.target.checked));

  // Secondary close-ups remain directly operable, with fictional preview content.
  const pinWidget = $('#pin-spiral');
  function resetPins() {
    pinWidget.setExample(WINDOWS.slice(0, 12), { pins: PINS, selected: 1 });
    pinWidget.selectPin(0, false);
    $('#pin-caption').textContent = 'Hover a pin to peek. Click to open.';
  }
  pinWidget.addEventListener('vortex-pin-select', (event) => {
    $('#pin-caption').textContent = event.detail.kind + ' · ' + event.detail.title;
  });
  pinWidget.addEventListener('vortex-pin', (event) => {
    $('#pin-caption').textContent = 'Demo: opened ' + event.detail.title + ' from the spiral.';
  });
  pinWidget.addEventListener('vortex-switch', (event) => {
    $('#pin-caption').textContent = 'Demo: selected ' + event.detail.title + '.';
  });
  $('#pin-reset').addEventListener('click', resetPins);

  const contextWidget = $('#context-spiral');
  let contextSelected = WINDOWS[1];
  function renderContext() {
    $('#context-menu .context-title img').src = contextSelected.src;
    $('#context-menu .context-title strong').textContent = contextSelected.meta;
    $('#context-menu .context-preview > strong').textContent = contextSelected.title;
    $('#context-menu .context-preview > p').textContent = contextSelected.body;
    $('#context-menu .context-meta strong').textContent = contextSelected.title;
    $('#context-menu .context-meta span').textContent = contextSelected.sub;
  }
  function resetContext() {
    contextSelected = WINDOWS[1];
    contextWidget.setExample(WINDOWS.slice(0, 12), { selected: 1 });
    $('#context-stage').dataset.placement = 'rest';
    $('#context-menu').hidden = false; $('#context-result').hidden = true;
    $('#context-caption').textContent = 'Try a window action in this example.';
    renderContext();
  }
  contextWidget.addEventListener('vortex-select', (event) => { contextSelected = event.detail; renderContext(); });
  contextWidget.addEventListener('vortex-switch', (event) => {
    contextSelected = event.detail; $('#context-menu').hidden = false; $('#context-result').hidden = true;
    $('#context-stage').dataset.placement = 'rest'; renderContext();
  });
  all('[data-window-action]').forEach((button) => button.addEventListener('click', () => {
    const action = button.dataset.windowAction;
    $('#context-menu').hidden = true;
    $('#context-stage').dataset.placement = action;
    if (action === 'close') {
      $('#context-result').hidden = true;
      contextWidget.setExample(WINDOWS.slice(0, 12).filter((item) => item.id !== contextSelected.id), { animate: !reduced });
      $('#context-caption').textContent = 'Closed ' + contextSelected.title + ' in the demo.';
    } else {
      $('#context-result').hidden = false;
      $('#context-result > div').lastChild.textContent = ' ' + contextSelected.title;
      const names = { left: 'Left half', right: 'Right half', fill: 'Fill the screen', display: 'Moved to the other display' };
      $('#context-caption').textContent = names[action] + ' · example window';
    }
    $('#context-reset').focus({ preventScroll: true });
  }));
  $('#context-reset').addEventListener('click', resetContext);

  // Five views of the same examples. Only the three rectangular layouts offer previews.
  const layoutRing = $('#layout-ring');
  const layoutCards = $('#layout-cards');
  const layoutPanel = $('#layout-preview');
  const thumbnailToggle = $('#layout-thumbnails');
  let layout = 'spiral';
  let layoutSelected = LAYOUT_WINDOWS[1];
  let preferPreviews = true;
  const layoutDescriptions = {
    spiral: 'Spiral · Icons around your pointer, with favorites tucked into the seam.',
    circular: 'Circular · Familiar icons in an even ring. Window previews are not used.',
    strip: 'Strip · A horizontal row of windows. Choose icons or window previews.',
    grid: 'Grid · More windows at a glance. Choose icons or window previews.',
    list: 'List · A compact list beside a larger view of the selected window.'
  };
  $('.layout-tabs').addEventListener('keydown', (event) => {
    const tabs = all('.layout-tabs [role="tab"]');
    const index = tabs.indexOf(document.activeElement);
    if (index < 0) return;
    let next = index;
    if (event.key === 'ArrowRight' || event.key === 'ArrowDown') next = (index + 1) % tabs.length;
    else if (event.key === 'ArrowLeft' || event.key === 'ArrowUp') next = (index + tabs.length - 1) % tabs.length;
    else if (event.key === 'Home') next = 0;
    else if (event.key === 'End') next = tabs.length - 1;
    else return;
    event.preventDefault();
    tabs[next].focus();
    tabs[next].click();
  });
  function selectLayoutItem(item) {
    layoutSelected = item;
    $('#layout-selection').textContent = item.title + ' · ' + item.meta;
    layoutCards.querySelectorAll('button').forEach((button) => {
      button.setAttribute('aria-pressed', String(button.dataset.window === item.id));
    });
    renderSelectedPreview();
  }
  function renderSelectedPreview() {
    const preview = $('#list-selected-preview');
    if (!preview) return;
    preview.replaceChildren();
    const icon = document.createElement('img');
    icon.src = layoutSelected.src; icon.alt = '';
    const title = document.createElement('strong');
    title.textContent = layoutSelected.title;
    const detail = document.createElement('p');
    detail.textContent = thumbnailToggle.checked ? layoutSelected.body : layoutSelected.meta;
    preview.append(icon, title, detail);
    preview.dataset.preview = String(thumbnailToggle.checked);
  }
  function renderLayouts() {
    const round = layout === 'spiral' || layout === 'circular';
    layoutRing.hidden = !round;
    layoutCards.hidden = round;
    thumbnailToggle.disabled = round;
    thumbnailToggle.checked = !round && preferPreviews;
    layoutPanel.dataset.layout = layout;
    $('#layout-description').textContent = layoutDescriptions[layout];
    $('#preview-availability').textContent = round ? 'Available in Strip, Grid & List' : 'Previews illustrated with sample content';
    $('#layout-pins').hidden = layout !== 'spiral';
    layoutPanel.setAttribute('aria-labelledby', 'layout-' + layout);
    all('[data-layout]').filter((el) => el.getAttribute('role') === 'tab').forEach((button) => {
      const active = button.dataset.layout === layout;
      button.setAttribute('aria-selected', String(active)); button.tabIndex = active ? 0 : -1;
    });
    if (round) {
      layoutRing.setExample(LAYOUT_WINDOWS, { selected: LAYOUT_WINDOWS.indexOf(layoutSelected), winding: layout, pins: layout === 'spiral' ? PINS : [] });
    } else {
      layoutCards.dataset.layout = layout;
      layoutCards.dataset.previews = String(thumbnailToggle.checked);
      layoutCards.replaceChildren();
      LAYOUT_WINDOWS.forEach((item) => {
        const button = document.createElement('button');
        button.type = 'button'; button.className = 'layout-card'; button.dataset.window = item.id;
        button.setAttribute('aria-label', item.title + ', ' + item.meta);
        button.setAttribute('aria-pressed', String(item.id === layoutSelected.id));
        const icon = document.createElement('img'); icon.src = item.src; icon.alt = '';
        const title = document.createElement('strong'); title.textContent = item.title;
        const app = document.createElement('span'); app.textContent = item.label;
        const preview = document.createElement('div'); preview.className = 'mini-preview'; preview.setAttribute('aria-hidden', 'true');
        const caption = document.createElement('b'); caption.textContent = item.title;
        const excerpt = document.createElement('span'); excerpt.textContent = item.detail;
        preview.append(caption, excerpt);
        button.append(icon, preview, title, app);
        button.addEventListener('click', () => selectLayoutItem(item));
        layoutCards.append(button);
      });
    }
    let selectedPreview = $('#list-selected-preview');
    if (!selectedPreview) {
      selectedPreview = document.createElement('article');
      selectedPreview.id = 'list-selected-preview';
      selectedPreview.setAttribute('aria-label', 'Larger view of the selected example window');
      layoutPanel.append(selectedPreview);
    }
    selectedPreview.hidden = layout !== 'list';
    renderSelectedPreview();
  }
  all('.layout-tabs button').forEach((button) => button.addEventListener('click', () => { layout = button.dataset.layout; renderLayouts(); }));
  thumbnailToggle.addEventListener('change', () => { preferPreviews = thumbnailToggle.checked; renderLayouts(); });
  layoutRing.addEventListener('vortex-select', (event) => selectLayoutItem(event.detail));
  layoutRing.addEventListener('vortex-switch', (event) => selectLayoutItem(event.detail));
  layoutRing.addEventListener('vortex-pin', (event) => {
    $('#layout-selection').textContent = event.detail.kind + ' · ' + event.detail.title;
  });
  layoutCards.addEventListener('keydown', (event) => {
    const buttons = [...layoutCards.querySelectorAll('button')];
    const index = buttons.indexOf(document.activeElement);
    if (index < 0 || !['ArrowDown','ArrowUp','ArrowRight','ArrowLeft'].includes(event.key)) return;
    event.preventDefault();
    const row = layout === 'grid' ? 3 : 1;
    const delta = event.key === 'ArrowDown' ? row : event.key === 'ArrowUp' ? -row : event.key === 'ArrowRight' ? 1 : -1;
    const next = buttons[(index + delta + buttons.length) % buttons.length];
    next.focus(); next.click();
  });
  const pinLegend = $('#layout-pins');
  pinLegend.replaceChildren();
  PINS.forEach((pin) => {
    const button = document.createElement('button');
    button.type = 'button'; button.textContent = pin.label || pin.title;
    button.setAttribute('aria-label', pin.kind + ': ' + pin.title);
    button.addEventListener('click', () => { $('#layout-selection').textContent = pin.kind + ' · ' + pin.title; });
    pinLegend.append(button);
  });


  all('a[href="#layouts"]').forEach((link) => link.addEventListener('click', () => { $('#layouts').open = true; }));
  customElements.whenDefined('vortex-spiral').then(() => {
    setAppearance(root.dataset.appearance || 'dark');
    applyReduced(reduced);
    fullWindowScene(false);
    resetPins();
    resetContext();
    renderLayouts();
    booted = true;
    if (visible && !document.hidden && !reduced) run(true);
    else { play.textContent = reduced ? 'Play' : 'Resume'; play.setAttribute('aria-pressed', 'false'); }
  });
  window.addEventListener('pagehide', () => { clearTimeout(timer); spiral.stopMotion(); });
})();
