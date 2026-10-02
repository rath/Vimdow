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

/* The install command stays selectable even without JavaScript or Clipboard API. */
(function () {
  'use strict';
  var button = document.querySelector('[data-copy-command]');
  var command = document.querySelector('[data-install-command]');
  var status = document.querySelector('[data-copy-status]');
  if (!button || !command || !status || !navigator.clipboard || !window.isSecureContext) { return; }
  var label = button.textContent;
  var reset;
  button.hidden = false;
  button.addEventListener('click', async function () {
    clearTimeout(reset);
    try {
      await navigator.clipboard.writeText(command.textContent);
      button.textContent = button.dataset.copied;
      status.textContent = button.dataset.copied;
    } catch (_) {
      var range = document.createRange();
      range.selectNodeContents(command);
      var selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
      status.textContent = button.dataset.copyFailed;
    }
    reset = setTimeout(function () { button.textContent = label; status.textContent = ''; }, 2000);
  });
})();
