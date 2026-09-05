/* Optical values shared by the website's interactive glass examples.
 * Motion matches Sources/VortexflowCore/Models/HubMotion.swift, not a rotating UI.
 */
(function (root, factory) {
  const optics = factory();
  if (typeof module === 'object' && module.exports) module.exports = optics;
  else root.VortexGlass = optics;
})(typeof window === 'undefined' ? globalThis : window, function () {
  'use strict';
  const TAU = Math.PI * 2;
  const frameInterval = 1000 / 24;
  const pulsePeriod = 3.8;
  const sheenPeriod = 7.6;
  const resting = Object.freeze({ energy: .55, phase: 0, radiusScale: 1, ripple: 0 });

  function sample(seconds, animated = true) {
    if (!animated) return resting;
    const time = Number.isFinite(seconds) ? seconds : 0;
    const breath = (time % pulsePeriod) / pulsePeriod * TAU;
    const phase = (time % sheenPeriod) / sheenPeriod * TAU;
    const energy = .5 + .5 * Math.sin(breath);
    return { energy, phase, radiusScale: 1 + .008 * Math.sin(breath),
      ripple: .018 * (.6 + .4 * energy) };
  }

  function radialScale(motion, angle) {
    return motion.radiusScale + motion.ripple *
      (Math.sin(3 * angle + motion.phase) + .32 * Math.sin(5 * angle - 2 * motion.phase));
  }

  function contour(radius, motion) {
    if (!Number.isFinite(radius) || radius <= 0) return '';
    const points = [];
    for (let index = 0; index < 180; index++) {
      const angle = index / 180 * TAU;
      const r = radius * radialScale(motion, angle);
      points.push((index ? 'L' : 'M') + (r * Math.cos(angle)).toFixed(3) + ' ' + (r * Math.sin(angle)).toFixed(3));
    }
    return points.join('') + 'Z';
  }

  function shouldAnimate({ connected, visible, hidden, reduced, paused }) {
    return Boolean(connected && visible && !hidden && !reduced && !paused);
  }

  // Existing example colors supply identity. Dark glass keeps that hue with a
  // low body luminance; neither appearance recolors monochrome app icons.
  function palette(hex = '#eeeeee') {
    const valid = /^#[\da-f]{6}$/i.test(hex) ? hex : '#eeeeee';
    const rgb = [1, 3, 5].map((offset) => parseInt(valid.slice(offset, offset + 2), 16) / 255);
    const max = Math.max(...rgb), min = Math.min(...rgb), delta = max - min;
    let hue = 0;
    if (delta) {
      if (max === rgb[0]) hue = ((rgb[1] - rgb[2]) / delta) % 6;
      else if (max === rgb[1]) hue = (rgb[2] - rgb[0]) / delta + 2;
      else hue = (rgb[0] - rgb[1]) / delta + 4;
      hue = (hue * 60 + 360) % 360;
    }
    const neutral = delta < .035;
    return {
      light: valid,
      dark: neutral ? '#16191a' : `hsl(${hue.toFixed(1)} 34% 12%)`,
      selectedDark: neutral ? '#1d4447' : `hsl(${hue.toFixed(1)} 48% 22%)`,
      rim: neutral ? '#e6edee' : `hsl(${hue.toFixed(1)} 52% 78%)`,
      glow: neutral ? '#c2f4e8' : `hsl(${hue.toFixed(1)} 65% 78%)`
    };
  }

  return Object.freeze({ frameInterval, pulsePeriod, sheenPeriod, resting,
    sample, radialScale, contour, shouldAnimate, palette });
});
