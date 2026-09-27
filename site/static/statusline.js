/* Vim-style ruler in the status line: "line,column" and Top / Bot / All / N%,
   following the page scroll the way Vim follows the cursor. */
(function () {
  'use strict';

  var lineElement = document.querySelector('[data-line]');
  var whereElement = document.querySelector('[data-where]');
  if (!lineElement || !whereElement) { return; }

  var queued = false;

  function update() {
    queued = false;
    var top = Math.max(0, window.scrollY);
    var max = document.documentElement.scrollHeight - window.innerHeight;
    var lineHeight = parseFloat(getComputedStyle(document.body).lineHeight) || 24;
    lineElement.textContent = (Math.floor(top / lineHeight) + 1) + ',1';
    if (max <= 0) { whereElement.textContent = 'All'; }
    else if (top <= 0) { whereElement.textContent = 'Top'; }
    else if (top >= max - 1) { whereElement.textContent = 'Bot'; }
    else { whereElement.textContent = Math.round(top / max * 100) + '%'; }
  }

  function schedule() {
    if (queued) { return; }
    queued = true;
    window.requestAnimationFrame(update);
  }

  window.addEventListener('scroll', schedule, { passive: true });
  window.addEventListener('resize', schedule);
  update();
})();
