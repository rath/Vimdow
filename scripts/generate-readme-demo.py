#!/usr/bin/env python3
"""Record the website's hero demo as docs/demo.gif for the README.

Builds the site, serves site/dist locally, and plays the English page in headless
Chrome on a simulated clock: requestAnimationFrame and every CSS transition are
advanced in fixed steps, so each frame lands at an exact time regardless of how
fast the machine is. One full loop is captured in the dark colour scheme, with
the caption under the stage and without the pause button, then encoded by ffmpeg
with a single palette and ordered dithering so unchanged areas stay identical
between frames. The fade between loops is left out: every pixel changes in a
fade, which would cost more than the rest of the loop, so the GIF cuts back to
its first frame instead. Chrome renders in software for steadier output, but two
runs can still differ by one colour level in a few frames, so regenerate the GIF
only when the demo itself changes.

Usage: scripts/generate-readme-demo.py   (needs Google Chrome and ffmpeg)
Environment: CHROME overrides the Chrome executable.
"""

from __future__ import annotations

import base64
import functools
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DIST = ROOT / "site" / "dist"
OUTPUT = ROOT / "docs" / "demo.gif"
CHROME = os.environ.get("CHROME", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome")

FPS = 25
VIEWPORT = {"width": 800, "height": 1000, "deviceScaleFactor": 1.25, "mobile": False}
PADDING = 16  # CSS pixels of page background around the stage and caption

# Runs before the page's scripts: frames and transitions only move when the
# recorder calls advance(), which returns whether the demo is between loops.
CLOCK = """
(() => {
  let now = 0;
  let queue = [];
  let handle = 0;
  const starts = new WeakMap();
  window.requestAnimationFrame = (callback) => { queue.push([++handle, callback]); return handle; };
  window.cancelAnimationFrame = (id) => { queue = queue.filter((entry) => entry[0] !== id); };
  function sync() {
    for (const animation of document.getAnimations()) {
      if (!starts.has(animation)) { starts.set(animation, now); animation.pause(); }
      animation.currentTime = now - starts.get(animation);
    }
  }
  window.__recorder = {
    advance(ms) {
      now += ms;
      const due = queue;
      queue = [];
      due.forEach((entry) => entry[1](now));
      sync();
      return document.querySelector('.desktop').classList.contains('is-resetting');
    },
  };
})();
"""

# Hides the pause button, the status line, and the fade between loops, scrolls
# the demo into view without the page's smooth scrolling (which runs on real time),
# and returns the capture area in document coordinates.
PREPARE = """
(async () => {
  await document.fonts.ready;
  const style = document.createElement('style');
  style.textContent = '[data-play], .statusline { display: none; } .desktop.is-resetting { opacity: 1; }';
  document.head.append(style);
  const demo = document.getElementById('demo');
  window.scrollTo({ top: demo.getBoundingClientRect().top + window.scrollY - %(padding)d, behavior: 'instant' });
  const stage = demo.querySelector('.stage').getBoundingClientRect();
  const controls = demo.querySelector('.demo-controls').getBoundingClientRect();
  return {
    x: stage.left + window.scrollX - %(padding)d,
    y: stage.top + window.scrollY - %(padding)d,
    width: stage.width + 2 * %(padding)d,
    height: controls.bottom - stage.top + 2 * %(padding)d,
    scale: 1,
  };
})()
""" % {"padding": PADDING}


class Browser:
    """Headless Chrome over --remote-debugging-pipe: NUL-separated JSON on fds 3 and 4."""

    def __init__(self, profile: str) -> None:
        flags = [
            "--headless=new", "--remote-debugging-pipe", f"--user-data-dir={profile}",
            "--no-first-run", "--no-default-browser-check", "--hide-scrollbars",
            "--force-color-profile=srgb", "--disable-gpu", "--mute-audio", "about:blank",
        ]
        # The shell hands our stdin and stdout to Chrome as fds 3 and 4.
        self.process = subprocess.Popen(
            ["/bin/sh", "-c", 'exec "$0" "$@" 3<&0 4>&1 </dev/null >/dev/null', CHROME, *flags],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        )
        self.buffer = bytearray()
        self.last_id = 0
        self.events: list[dict] = []

    def send(self, method: str, params: dict | None = None, session: str | None = None) -> dict:
        self.last_id += 1
        message = {"id": self.last_id, "method": method, "params": params or {}}
        if session:
            message["sessionId"] = session
        self.process.stdin.write(json.dumps(message).encode() + b"\0")
        self.process.stdin.flush()
        while True:
            reply = self.receive()
            if reply.get("id") == self.last_id:
                if "error" in reply:
                    raise SystemExit(f"generate-readme-demo: {method}: {reply['error'].get('message')}")
                return reply["result"]
            self.events.append(reply)

    def wait_for(self, method: str) -> None:
        while not any(event.get("method") == method for event in self.events):
            self.events.append(self.receive())
        self.events.clear()

    def receive(self) -> dict:
        while (end := self.buffer.find(b"\0")) < 0:
            chunk = self.process.stdout.read1(1 << 20)
            if not chunk:
                raise SystemExit("generate-readme-demo: Chrome exited unexpectedly")
            self.buffer += chunk
        message = bytes(self.buffer[:end])
        del self.buffer[:end + 1]
        return json.loads(message)

    def close(self) -> None:
        self.process.stdin.close()
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        pass


def evaluate(browser: Browser, session: str, expression: str):
    result = browser.send("Runtime.evaluate", {
        "expression": expression, "awaitPromise": True, "returnByValue": True,
    }, session)
    if "exceptionDetails" in result:
        raise SystemExit(f"generate-readme-demo: {result['exceptionDetails'].get('text')}: {expression[:60]}")
    return result["result"].get("value")


def record(url: str, frames: Path) -> int:
    with tempfile.TemporaryDirectory(prefix="vimdow-chrome-") as profile:
        browser = Browser(profile)
        try:
            target = browser.send("Target.createTarget", {"url": "about:blank"})["targetId"]
            session = browser.send("Target.attachToTarget", {"targetId": target, "flatten": True})["sessionId"]
            browser.send("Page.enable", session=session)
            browser.send("Emulation.setDeviceMetricsOverride", VIEWPORT, session)
            browser.send("Emulation.setEmulatedMedia", {"features": [
                {"name": "prefers-color-scheme", "value": "dark"},
                {"name": "prefers-reduced-motion", "value": "no-preference"},
            ]}, session)
            browser.send("Page.addScriptToEvaluateOnNewDocument", {"source": CLOCK}, session)
            browser.send("Page.navigate", {"url": url}, session)
            browser.wait_for("Page.loadEventFired")
            clip = evaluate(browser, session, PREPARE)

            step = f"window.__recorder.advance({1000 / FPS})"
            limit = 60 * FPS  # a loop is well under a minute
            count = 0
            between_loops = False
            while count < limit:
                now_between = evaluate(browser, session, step)
                if between_loops and not now_between:
                    return count  # the next loop starts with the first frame again
                between_loops = now_between
                shot = browser.send("Page.captureScreenshot", {"format": "png", "clip": clip}, session)
                (frames / f"{count:04d}.png").write_bytes(base64.b64decode(shot["data"]))
                count += 1
            raise SystemExit("generate-readme-demo: the demo loop did not end within a minute")
        finally:
            browser.close()


def main() -> int:
    if shutil.which("ffmpeg") is None:
        raise SystemExit("generate-readme-demo: ffmpeg not found (brew install ffmpeg)")
    if not Path(CHROME).is_file():
        raise SystemExit(f"generate-readme-demo: Chrome not found at {CHROME}; set CHROME")
    subprocess.run([sys.executable, str(ROOT / "site" / "build.py")], check=True)

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), functools.partial(QuietHandler, directory=str(DIST)))
    threading.Thread(target=server.serve_forever, daemon=True).start()
    try:
        with tempfile.TemporaryDirectory(prefix="vimdow-demo-") as work:
            frames = Path(work)
            count = record(f"http://127.0.0.1:{server.server_address[1]}/", frames)
            OUTPUT.parent.mkdir(exist_ok=True)
            subprocess.run([
                "ffmpeg", "-v", "error", "-y", "-framerate", str(FPS), "-i", str(frames / "%04d.png"),
                "-filter_complex",
                "[0:v]split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];"
                "[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle",
                "-loop", "0", str(OUTPUT),
            ], check=True)
    finally:
        server.shutdown()
    size = OUTPUT.stat().st_size
    print(f"wrote {OUTPUT.relative_to(ROOT)}: {count} frames at {FPS} fps, {size / 1_000_000:.1f} MB")
    return 0


if __name__ == "__main__":
    sys.exit(main())
