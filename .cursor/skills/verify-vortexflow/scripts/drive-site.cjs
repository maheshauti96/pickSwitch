#!/usr/bin/env node
// Headless Chrome CDP driver for the VortexFlow site. No extra packages.
'use strict';

const { spawn } = require('child_process');
const fs = require('fs');
const http = require('http');
const net = require('net');
const path = require('path');
const { setTimeout: delay } = require('timers/promises');

const CHROME =
  process.env.VERIFY_CHROME ||
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

function die(msg) {
  console.error(msg);
  process.exit(1);
}

function freePort() {
  return new Promise((resolve, reject) => {
    const server = net.createServer();
    server.listen(0, '127.0.0.1', () => {
      const { port } = server.address();
      server.close((err) => (err ? reject(err) : resolve(port)));
    });
    server.on('error', reject);
  });
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    http
      .get(url, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          try {
            resolve(JSON.parse(body));
          } catch (err) {
            reject(err);
          }
        });
      })
      .on('error', reject);
  });
}

async function waitFor(fn, ms = 15000) {
  const start = Date.now();
  let last;
  while (Date.now() - start < ms) {
    try {
      return await fn();
    } catch (err) {
      last = err;
      await delay(150);
    }
  }
  throw last || new Error('timed out');
}

class Cdp {
  constructor(ws) {
    this.ws = ws;
    this.next = 1;
    this.pending = new Map();
    this.events = new Map();
    ws.addEventListener('message', (ev) => {
      const msg = JSON.parse(ev.data);
      if (msg.id && this.pending.has(msg.id)) {
        const { resolve, reject } = this.pending.get(msg.id);
        this.pending.delete(msg.id);
        if (msg.error) reject(new Error(msg.error.message));
        else resolve(msg.result);
        return;
      }
      if (msg.method && this.events.has(msg.method)) {
        this.events.get(msg.method)(msg.params);
      }
    });
  }
  send(method, params = {}) {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.ws.send(JSON.stringify({ id, method, params }));
    });
  }
  once(method) {
    return new Promise((resolve) => this.events.set(method, resolve));
  }
}

async function withChrome(url, fn) {
  if (!fs.existsSync(CHROME)) die(`Chrome not found at ${CHROME}`);
  const debugPort = await freePort();
  const profile = fs.mkdtempSync(path.join(require('os').tmpdir(), 'vf-chrome-'));
  const chrome = spawn(
    CHROME,
    [
      '--headless=new',
      '--disable-gpu',
      '--hide-scrollbars',
      '--window-size=1440,900',
      `--remote-debugging-port=${debugPort}`,
      `--user-data-dir=${profile}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-dev-shm-usage',
      'about:blank',
    ],
    { stdio: ['ignore', 'pipe', 'pipe'] }
  );
  let ws;
  try {
    const pages = await waitFor(async () => {
      const list = await getJson(`http://127.0.0.1:${debugPort}/json/list`);
      const page = list.find((t) => t.type === 'page' && t.webSocketDebuggerUrl);
      if (!page) throw new Error('no page target');
      return page;
    });
    ws = new WebSocket(pages.webSocketDebuggerUrl);
    await new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve);
      ws.addEventListener('error', reject);
    });
    const cdp = new Cdp(ws);
    await cdp.send('Page.enable');
    await cdp.send('Runtime.enable');
    const loaded = cdp.once('Page.loadEventFired');
    await cdp.send('Page.navigate', { url });
    await loaded;
    await delay(400);
    return await fn(cdp);
  } finally {
    try {
      if (ws && ws.readyState === 1) ws.close();
    } catch {}
    chrome.kill('SIGTERM');
    await delay(200);
    try {
      chrome.kill('SIGKILL');
    } catch {}
    fs.rmSync(profile, { recursive: true, force: true });
  }
}

async function screenshot(cdp, outPath) {
  const { data } = await cdp.send('Page.captureScreenshot', {
    format: 'png',
    fromSurface: true,
  });
  fs.mkdirSync(path.dirname(outPath), { recursive: true });
  fs.writeFileSync(outPath, Buffer.from(data, 'base64'));
}

async function evalJson(cdp, expression) {
  const result = await cdp.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  });
  if (result.exceptionDetails) {
    throw new Error(result.exceptionDetails.text || 'evaluate failed');
  }
  return result.result.value;
}

const cmds = {
  async screenshot(pageUrl, outPath) {
    if (!pageUrl || !outPath) die('usage: drive-site.cjs screenshot URL OUT.png');
    await withChrome(pageUrl, async (cdp) => {
      await screenshot(cdp, outPath);
    });
    console.log(outPath);
  },

  async eval(pageUrl, expression) {
    if (!pageUrl || !expression) die('usage: drive-site.cjs eval URL EXPRESSION');
    const value = await withChrome(pageUrl, (cdp) => evalJson(cdp, expression));
    console.log(JSON.stringify(value, null, 2));
  },

  async 'download-page'(pageUrl, outDir) {
    if (!pageUrl || !outDir) die('usage: drive-site.cjs download-page URL OUTDIR');
    fs.mkdirSync(outDir, { recursive: true });
    const report = await withChrome(pageUrl, async (cdp) => {
      const before = await evalJson(
        cdp,
        `({
          title: document.title,
          h1: document.querySelector('h1') && document.querySelector('h1').innerText,
          gatekeeper: Boolean(document.querySelector('#gatekeeper')),
          downloadHref: document.querySelector('[data-download]') && document.querySelector('[data-download]').href,
          steps: [...document.querySelectorAll('ol.steps li')].map((li) => li.innerText.trim())
        })`
      );
      await screenshot(cdp, path.join(outDir, 'download-before.png'));
      await evalJson(
        cdp,
        `document.querySelector('#gatekeeper').scrollIntoView({ block: 'start' }); true`
      );
      await delay(250);
      await screenshot(cdp, path.join(outDir, 'download-gatekeeper.png'));
      const after = await evalJson(
        cdp,
        `({
          heading: document.querySelector('#gatekeeper').innerText,
          visible: document.querySelector('#gatekeeper').getBoundingClientRect().top < innerHeight
        })`
      );
      return { before, after };
    });
    fs.writeFileSync(path.join(outDir, 'download.json'), JSON.stringify(report, null, 2));
    console.log(path.join(outDir, 'download.json'));
  },

  async 'home-spiral'(pageUrl, outDir) {
    if (!pageUrl || !outDir) die('usage: drive-site.cjs home-spiral URL OUTDIR');
    fs.mkdirSync(outDir, { recursive: true });
    const report = await withChrome(pageUrl, async (cdp) => {
      const ready = await evalJson(
        cdp,
        `({
          title: document.title,
          h1: document.querySelector('#hero-h') && document.querySelector('#hero-h').innerText.replace(/\\s+/g, ' ').trim(),
          demo: Boolean(document.querySelector('#product-demo')),
          searchBtn: Boolean(document.querySelector('#story-search'))
        })`
      );
      await screenshot(cdp, path.join(outDir, 'home-before.png'));
      await evalJson(
        cdp,
        `document.querySelector('#product-demo').scrollIntoView({ block: 'center' });
         document.querySelector('#story-search').click();
         true`
      );
      await delay(600);
      const typed = await evalJson(
        cdp,
        `(() => {
          const spiral = document.querySelector('#hero-spiral');
          const input = spiral && spiral.shadowRoot && spiral.shadowRoot.querySelector('.qinput');
          if (!input) return { ok: false, reason: 'no search input' };
          input.focus();
          input.value = '';
          const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
          setter.call(input, 'snowfl');
          input.dispatchEvent(new InputEvent('input', { bubbles: true, data: 'snowfl' }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
          spiral.dispatchEvent(new CustomEvent('vortex-query', { detail: 'snowfl', bubbles: true }));
          return {
            ok: true,
            value: input.value,
            caption: (document.querySelector('#story-caption') || {}).textContent || '',
            instruction: (document.querySelector('#story-instruction') || {}).textContent || ''
          };
        })()`
      );
      await delay(400);
      await screenshot(cdp, path.join(outDir, 'home-search.png'));
      return { ready, typed };
    });
    fs.writeFileSync(path.join(outDir, 'home-spiral.json'), JSON.stringify(report, null, 2));
    console.log(path.join(outDir, 'home-spiral.json'));
  },
};

const [cmd, ...args] = process.argv.slice(2);
if (!cmd || !cmds[cmd]) {
  die(
    'usage: drive-site.cjs screenshot|eval|download-page|home-spiral ...'
  );
}
cmds[cmd](...args).catch((err) => die(err.stack || String(err)));
