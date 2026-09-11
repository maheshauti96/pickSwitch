const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const glass = require('../../site/js/vortex-glass.js');
const root = path.resolve(__dirname, '../..');

test('web motion keeps the native app timing and waveform', () => {
  const native = fs.readFileSync(path.join(root, 'Sources/VortexflowCore/Models/HubChrome.swift'), 'utf8');
  const motion = fs.readFileSync(path.join(root, 'Sources/VortexflowCore/Models/HubMotion.swift'), 'utf8');
  assert.match(native, new RegExp(`pulsePeriod.*= ${glass.pulsePeriod}`));
  assert.match(native, new RegExp(`sheenPeriod.*= ${glass.sheenPeriod}`));
  assert.match(motion, /1\.0 \/ 24\.0/);
  assert.equal(glass.frameInterval, 1000 / 24);
  for (let t = 0; t < 12; t += .1) {
    const sample = glass.sample(t);
    const breath = t % 3.8 / 3.8 * 2 * Math.PI;
    assert.equal(sample.energy, .5 + .5 * Math.sin(breath));
    assert.equal(sample.radiusScale, 1 + .008 * Math.sin(breath));
  }
});

test('rim moves without leaving the native four-percent optical bound', () => {
  for (let time = 0; time < 15.2; time += 1 / 24) {
    const sample = glass.sample(time);
    assert.ok(sample.energy >= 0 && sample.energy <= 1);
    for (let angle = 0; angle < Math.PI * 2; angle += .1) {
      const radius = glass.radialScale(sample, angle);
      assert.ok(radius >= .96 && radius <= 1.04);
    }
  }
  assert.notEqual(glass.contour(89, glass.sample(0)), glass.contour(89, glass.sample(1.1)));
});

test('resting contour is static and well formed', () => {
  assert.equal(glass.sample(0, false), glass.sample(50, false));
  assert.equal(glass.contour(0, glass.resting), '');
  const contour = glass.contour(89, glass.resting);
  assert.equal((contour.match(/L/g) || []).length, 179);
  assert.match(contour, /^M89\.000 0\.000L/);
  assert.ok(contour.endsWith('Z'));
  assert.ok(!contour.includes('NaN'));
});

test('hidden, disconnected, reduced and explicitly paused examples do not animate', () => {
  const active = { connected: true, visible: true, hidden: false, reduced: false, paused: false };
  assert.equal(glass.shouldAnimate(active), true);
  for (const [key, value] of [['connected', false], ['visible', false], ['hidden', true], ['reduced', true], ['paused', true]]) {
    assert.equal(glass.shouldAnimate({ ...active, [key]: value }), false);
  }
});

test('the traveling light loops continuously', () => {
  const before = glass.sample(glass.sheenPeriod - .0001);
  const after = glass.sample(glass.sheenPeriod + .0001);
  for (let angle = 0; angle < Math.PI * 2; angle += .1) {
    assert.ok(Math.abs(glass.radialScale(before, angle) - glass.radialScale(after, angle)) < .001);
  }
});

test('neutral and colored app identities survive both material palettes', () => {
  assert.equal(glass.palette('#f0f0ed').dark, '#16191a');
  assert.notEqual(glass.palette('#eaf6f2').dark, glass.palette('#f8e9ef').dark);
  assert.equal(glass.palette('bad;url(example)').light, '#eeeeee');
  assert.equal(glass.palette('#f8e9ef').light, '#f8e9ef');
});

test('all four showcase widgets opt into glass, loaded before the component', () => {
  const html = fs.readFileSync(path.join(root, 'site/index.html'), 'utf8');
  assert.equal((html.match(/<vortex-spiral[^>]*\bglass\b/g) || []).length, 4);
  assert.ok(html.indexOf('/js/vortex-glass.js') < html.indexOf('/js/vortex-spiral.js'));
  assert.match(html, /aria-label="Demo appearance"/);
  assert.match(html, /data-appearance-choice="light"/);
  assert.match(html, /data-appearance-choice="dark"/);
  assert.match(html, /Free\. Open source\. Forever\./);
  assert.doesNotMatch(html, /\$5|seven days free|Join the waitlist|formsubmit/i);
});

test('the static page and showcase keep valid local assets and metadata', () => {
  const html = fs.readFileSync(path.join(root, 'site/index.html'), 'utf8');
  const scenes = fs.readFileSync(path.join(root, 'site/js/showcase.js'), 'utf8');
  const assets = new Set([...html.matchAll(/(?:src|href)="(\/(?:css|js|img)\/[^\"]+)"/g)].map(m => m[1].split('?')[0]));
  for (const match of scenes.matchAll(/src: '(\/img\/[^']+)'/g)) assets.add(match[1]);
  for (const asset of assets) assert.ok(fs.existsSync(path.join(root, 'site', asset)), asset);
  const metadata = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1];
  const graph = JSON.parse(metadata)['@graph'];
  assert.equal(graph.length, 3);
  const app = graph.find((node) => node['@type'] === 'SoftwareApplication');
  assert.equal(app.isAccessibleForFree, true);
  assert.equal(app.offers.price, '0');
  assert.match(graph.find((node) => node['@type'] === 'SoftwareSourceCode').codeRepository, /github\.com\//);
});

test('the hero story opens the overlay itself and keeps looping', () => {
  const html = fs.readFileSync(path.join(root, 'site/index.html'), 'utf8');
  const scenes = fs.readFileSync(path.join(root, 'site/js/showcase.js'), 'utf8');
  assert.match(html, /id="story-trigger"[^>]*\bhidden\b/);
  assert.match(html, /<kbd>⌃<\/kbd><kbd>⌥<\/kbd><kbd>space<\/kbd>/);
  assert.match(scenes, /closedScene\(loops % 2 \? 'keys' : 'mouse'\)/);
  assert.match(scenes, /event\.detail\.kind !== 'hover'\) pause\('manual'\)/);
  assert.doesNotMatch(scenes, /completed/);
  const widget = fs.readFileSync(path.join(root, 'site/js/vortex-spiral.js'), 'utf8');
  assert.match(widget, /^\s+playEntrance\(\) \{/m);
});
