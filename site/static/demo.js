/* Animated command-mode demo. Reads its steps from #demo-config (language-neutral)
   and highlights the localized step list rendered by the build. */
(function () {
  'use strict';

  var root = document.getElementById('demo');
  var configElement = document.getElementById('demo-config');
  if (!root || !configElement) { return; }

  var config = JSON.parse(configElement.textContent);
  var stage = root.querySelector('.stage');
  var windowElement = root.querySelector('.window');
  var keysElement = root.querySelector('[data-keys]');
  var modeElement = root.querySelector('[data-mode]');
  var button = root.querySelector('[data-play]');
  var stepItems = Array.prototype.slice.call(root.querySelectorAll('[data-step]'));
  var steps = config.steps;

  var KEY_DELAY = 260;   // ms between key caps appearing
  var MOVE_TIME = 500;   // matches the CSS transition on .window
  var HOLD_TIME = 1100;  // pause after each step
  var LOOP_PAUSE = 1800; // pause before the loop restarts

  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  function applyFrame(frame) {
    var stageSize = config.stage;
    windowElement.style.left = (frame.x / stageSize.width * 100) + '%';
    windowElement.style.top = (frame.y / stageSize.height * 100) + '%';
    windowElement.style.width = (frame.w / stageSize.width * 100) + '%';
    windowElement.style.height = (frame.h / stageSize.height * 100) + '%';
  }

  function setMode(mode) {
    var command = mode === 'command';
    modeElement.textContent = command ? modeElement.dataset.command : modeElement.dataset.normal;
    stage.classList.toggle('is-command', command);
  }

  function showKeys(keys, count) {
    var caps = keys.slice(0, count).map(function (key) {
      var cap = document.createElement('kbd');
      cap.textContent = key;
      return cap;
    });
    keysElement.replaceChildren.apply(keysElement, caps);
  }

  function highlight(index) {
    stepItems.forEach(function (item, position) {
      item.classList.toggle('is-active', position === index);
    });
  }

  function reset() {
    applyFrame(config.initialFrame);
    setMode('normal');
    showKeys([], 0);
    highlight(-1);
  }

  function applyStep(step) {
    if (step.frame) { applyFrame(step.frame); }
    setMode(step.mode);
  }

  /* Build one loop as a list of timed events. */
  function timeline() {
    var events = [];
    var cursor = 400;
    steps.forEach(function (step, index) {
      step.keys.forEach(function (_, keyIndex) {
        events.push({ at: cursor + keyIndex * KEY_DELAY, run: function () {
          if (keyIndex === 0) { highlight(index); }
          showKeys(step.keys, keyIndex + 1);
        } });
      });
      cursor += step.keys.length * KEY_DELAY;
      events.push({ at: cursor, run: function () { applyStep(step); } });
      cursor += (step.frame ? MOVE_TIME : 150) + HOLD_TIME;
    });
    events.push({ at: cursor, run: function () { showKeys([], 0); highlight(-1); } });
    return { events: events, duration: cursor + LOOP_PAUSE };
  }

  /* Reduced motion: no autoplay; the button steps through the sequence. */
  if (reducedMotion.matches) {
    var position = -1;
    reset();
    var lastFrame = config.initialFrame;
    steps.forEach(function (step) { if (step.frame) { lastFrame = step.frame; } });
    applyFrame(lastFrame);
    button.textContent = button.dataset.nextLabel;
    button.removeAttribute('aria-pressed');
    button.addEventListener('click', function () {
      position += 1;
      if (position >= steps.length) {
        position = -1;
        reset();
        applyFrame(lastFrame);
        return;
      }
      if (position === 0) { reset(); }
      var step = steps[position];
      showKeys(step.keys, step.keys.length);
      applyStep(step);
      highlight(position);
    });
    return;
  }

  var loop = timeline();
  var wantsPlay = true;   // the visitor's choice
  var pageVisible = !document.hidden;
  var inView = true;
  var elapsed = 0;
  var nextEvent = 0;
  var lastTick = null;
  var frameRequest = null;

  function playing() { return wantsPlay && pageVisible && inView; }

  function tick(now) {
    frameRequest = null;
    if (!playing()) { lastTick = null; return; }
    if (lastTick !== null) { elapsed += now - lastTick; }
    lastTick = now;
    while (nextEvent < loop.events.length && loop.events[nextEvent].at <= elapsed) {
      loop.events[nextEvent].run();
      nextEvent += 1;
    }
    if (elapsed >= loop.duration) {
      elapsed = 0;
      nextEvent = 0;
      reset();
    }
    frameRequest = window.requestAnimationFrame(tick);
  }

  function schedule() {
    if (playing() && frameRequest === null) {
      lastTick = null;
      frameRequest = window.requestAnimationFrame(tick);
    }
  }

  function updateButton() {
    button.textContent = wantsPlay ? button.dataset.pauseLabel : button.dataset.playLabel;
    button.setAttribute('aria-pressed', wantsPlay ? 'true' : 'false');
  }

  button.addEventListener('click', function () {
    wantsPlay = !wantsPlay;
    updateButton();
    schedule();
  });

  document.addEventListener('visibilitychange', function () {
    pageVisible = !document.hidden;
    schedule();
  });

  if ('IntersectionObserver' in window) {
    new IntersectionObserver(function (entries) {
      inView = entries[0].isIntersecting;
      schedule();
    }, { threshold: 0.2 }).observe(stage);
  }

  reset();
  updateButton();
  schedule();
})();
