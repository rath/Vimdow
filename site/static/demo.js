/* Animated command-mode demo. Reads its windows and keys from #demo-config
   (language-neutral) and takes each step's caption from the localized step list
   rendered by the build. Every key applies its own effect as it is pressed. */
(function () {
  'use strict';

  var root = document.getElementById('demo');
  var configElement = document.getElementById('demo-config');
  if (!root || !configElement) { return; }

  var config = JSON.parse(configElement.textContent);
  var stage = root.querySelector('.stage');
  var desktop = root.querySelector('.desktop');
  var ghost = root.querySelector('[data-ghost]');
  var hud = root.querySelector('[data-hud]');
  var keysElement = root.querySelector('[data-keys]');
  var caption = root.querySelector('[data-caption]');
  var modeElement = root.querySelector('[data-mode]');
  var button = root.querySelector('[data-play]');
  var stepItems = Array.prototype.slice.call(root.querySelectorAll('[data-step]'));
  var steps = config.steps;
  var names = Object.keys(config.windows);
  var windows = {};
  names.forEach(function (name) { windows[name] = root.querySelector('[data-window="' + name + '"]'); });

  var LEAD_TIME = 300;   // ms between a step's caption and its first key
  var KEY_DELAY = 360;   // ms between keys; each key's motion fits inside it
  var HOLD_TIME = 1000;  // pause after each step
  var LOOP_PAUSE = 2200; // time on the last frame before the loop restarts
  var FADE_TIME = 250;   // matches the opacity transition on .desktop

  var reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  var state;

  function place(element, frame) {
    var size = config.stage;
    element.style.left = (frame.x / size.width * 100) + '%';
    element.style.top = (frame.y / size.height * 100) + '%';
    element.style.width = (frame.w / size.width * 100) + '%';
    element.style.height = (frame.h / size.height * 100) + '%';
  }

  function setMode(mode) {
    state.mode = mode;
    var command = mode === 'command';
    modeElement.textContent = command ? modeElement.dataset.command : modeElement.dataset.normal;
    stage.classList.toggle('is-command', command);
  }

  function setFocus(name) {
    state.focus = name;
    stage.dataset.focus = name;
  }

  /* Like the app, number windows by their horizontal position. */
  function setGuides(visible) {
    var order = names.slice().sort(function (a, b) { return state.frames[a].x - state.frames[b].x; });
    order.forEach(function (name, index) {
      windows[name].querySelector('[data-guide]').textContent = String(index + 1);
    });
    stage.classList.toggle('show-guides', visible);
  }

  function showGhost(frame) {
    place(ghost, frame);
    ghost.classList.add('is-visible');
    void ghost.offsetWidth;  // commit the visible state so removing the class fades it out
    ghost.classList.remove('is-visible');
  }

  function press(key, animate) {
    if (key.focus) { setFocus(key.focus); }
    if (key.mode) { setMode(key.mode); }
    if ('guides' in key) { setGuides(key.guides); }
    if (key.frame) {
      var previous = state.frames[state.focus];
      var next = Object.assign({}, previous, key.frame);
      if (animate) { showGhost(previous); }
      state.frames[state.focus] = next;
      place(windows[state.focus], next);
    }
  }

  function showKeys(step, count) {
    var caps = step ? step.keys.slice(0, count).map(function (key) {
      var cap = document.createElement('kbd');
      cap.textContent = key.key;
      return cap;
    }) : [];
    keysElement.replaceChildren.apply(keysElement, caps);
    hud.classList.toggle('is-visible', caps.length > 0);
  }

  function showCaption(index) {
    stepItems.forEach(function (item, position) {
      item.classList.toggle('is-active', position === index);
    });
    if (index < 0) { caption.replaceChildren(); return; }
    var count = document.createElement('span');
    count.className = 'count';
    count.textContent = (index + 1) + '/' + steps.length;
    caption.replaceChildren(count, stepItems[index].textContent);
  }

  /* Jump to the state before any key, without animating the windows back. */
  function reset() {
    state = { frames: {}, focus: names[0], mode: 'normal' };
    stage.classList.add('is-instant');
    names.forEach(function (name) {
      state.frames[name] = Object.assign({}, config.windows[name]);
      place(windows[name], state.frames[name]);
    });
    setFocus(names[0]);
    setMode('normal');
    setGuides(false);
    void stage.offsetWidth;
    stage.classList.remove('is-instant');
    showKeys(null, 0);
    showCaption(-1);
  }

  /* The state after the given number of steps, applied at once. */
  function jumpTo(stepCount) {
    reset();
    stage.classList.add('is-instant');
    steps.slice(0, stepCount).forEach(function (step) {
      step.keys.forEach(function (key) { press(key, false); });
    });
    void stage.offsetWidth;
    stage.classList.remove('is-instant');
  }

  /* One loop as a list of timed events. */
  function timeline() {
    var events = [];
    var cursor = 600;
    steps.forEach(function (step, index) {
      events.push({ at: cursor, run: function () { showCaption(index); showKeys(step, 0); } });
      var at = cursor + LEAD_TIME;
      step.keys.forEach(function (key, keyIndex) {
        events.push({ at: at, run: function () {
          showKeys(step, keyIndex + 1);
          press(key, true);
        } });
        at += KEY_DELAY + (key.hold || 0);  // hold: extra time to look before the next key
      });
      cursor = at + HOLD_TIME;
    });
    events.push({ at: cursor, run: function () { showKeys(null, 0); showCaption(-1); } });
    cursor += LOOP_PAUSE;
    events.push({ at: cursor, run: function () { desktop.classList.add('is-resetting'); } });
    return { events: events, duration: cursor + FADE_TIME };
  }

  /* Reduced motion: no autoplay. The page shows the last frame, the step list
     stays visible, and the button steps through the sequence. */
  if (reducedMotion.matches) {
    var position = -1;
    jumpTo(steps.length);
    button.textContent = button.dataset.nextLabel;
    button.removeAttribute('aria-pressed');
    button.addEventListener('click', function () {
      position += 1;
      if (position >= steps.length) {
        position = -1;
        jumpTo(steps.length);
        return;
      }
      jumpTo(position + 1);
      showKeys(steps[position], steps[position].keys.length);
      showCaption(position);
    });
    return;
  }

  root.classList.add('is-live');
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
      desktop.classList.remove('is-resetting');
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
