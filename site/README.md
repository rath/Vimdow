# Vimdow website

Source for <https://vimdow.told.me>: one static page in English, Korean,
Japanese, and Simplified Chinese, built by a standard-library Python script and
deployed to GitHub Pages by `.github/workflows/site.yml`.

## Build and preview

```sh
python3 site/build.py
python3 -m http.server -d site/dist 8000
```

The output in `site/dist/` is ignored by Git. Pages are written to `/`, `/ko/`,
`/ja/`, and `/zh/`, with `sitemap.xml`, `404.html`, and the static files. The
app icon is copied from `Artwork/launcher.svg` at build time.

The build fails when a language file is missing or has extra keys compared with
`content/en.json`, when a key is never used, when a page has unbalanced tags, or
when a root-relative link points at nothing in `dist`.

## Layout

- `content/_shared.json`: language-neutral structure. Site URLs, the language
  list, demo steps with their key caps and window frames, and the cheat-sheet
  rows with their keys. Key caps are never translated.
- `content/en.json`: all copy, and the source of truth for keys. `ko.json`,
  `ja.json`, and `zh-Hans.json` mirror it exactly.
- `templates/index.html`: the page. `{{key}}` inserts escaped text; `{{{key}}}`
  inserts raw HTML and is allowed only for keys ending in `_html` and for
  fragments the build renders itself (`_.` keys). The small `*.html` fragments
  beside it are rendered per item with `string.Template`.
- `static/`: stylesheet, demo script, robots, 404, and rendered images. CSS and
  JS URLs carry a content hash so GitHub Pages' cache never serves stale files.
- `artwork/og.svg`: source for `static/og.png`. After editing it or the app
  icon, run `./scripts/generate-site-images.sh` (needs `rsvg-convert`).
- `media/`: drop the real recording here (see below).

Change all four language files together. `git diff --check` and a successful
build are enough verification for copy-only changes.

## Translations

Korean is reviewed by the owner. Japanese and Simplified Chinese were drafted
without a native-speaker review; have someone fluent read them before promoting
the site widely. Keep key names (`hjkl`, `Control–W`, `zz`) in Latin script in
every language, and keep the `_html` strings' `<kbd>` markup intact.

## Adding a language

1. Add an entry to `languages` in `content/_shared.json` with its BCP 47 `lang`,
   URL `path` (trailing slash), `ogLocale`, and a label written in that language.
2. Copy `content/en.json` to `content/<file>.json` and translate every value.
3. Add a `:lang()` font stack in `static/style.css` if the script needs one.
4. Add the link to `static/404.html`. Build; the checks report anything missed.

## Real recording

The hero currently plays an animated mock-up. To add a real screen recording:

1. Use one display at 1440×900 with a plain wallpaper and a single window, for
   example TextEdit. Install KeyCastr (`brew install --cask keycastr`) so
   keystrokes appear on screen.
2. Record with QuickTime Player (File → New Screen Recording) or
   `screencapture -v recording.mov`, following the demo's sequence:
   Control–Option–A, `lll`, `12j`, Option–`lll`, `zz`, Control–W then `H`, `u`,
   Escape. Keep it under 30 seconds.
3. Encode with ffmpeg (external tool, `brew install ffmpeg`), aiming for under 5 MB:

   ```sh
   ffmpeg -i recording.mov -vf "scale=1280:-2,fps=30" -c:v libx264 -crf 28 \
     -pix_fmt yuv420p -movflags +faststart -an site/media/demo.mp4
   ffmpeg -i recording.mov -vf "scale=1280:-2,fps=30" -c:v libvpx-vp9 -b:v 0 -crf 36 \
     -an site/media/demo.webm
   ffmpeg -ss 1 -i site/media/demo.mp4 -frames:v 1 -q:v 3 site/media/demo.jpg
   ```

4. Rebuild. When `media/demo.mp4` exists, every page gains a "Watch a real
   recording" section under the animated demo; `demo.webm` and `demo.jpg` are
   used when present. Commit the files plainly; Pages does not serve Git LFS.

## Deployment

Pushes to `master` that touch `site/`, `Artwork/`, or the workflow build and
deploy the site. One-time setup, in this order:

1. DNS at the `told.me` registrar: `CNAME vimdow → rath.github.io.` Do this
   before setting the domain in GitHub so its verification passes.
2. Enable Pages with the GitHub Actions source:

   ```sh
   gh api -X POST repos/rath/Vimdow/pages -f build_type=workflow
   ```

3. After the first successful deploy, set the domain, then enforce HTTPS once
   the certificate has been issued (minutes to an hour after DNS propagates):

   ```sh
   gh api -X PUT repos/rath/Vimdow/pages -f cname=vimdow.told.me
   gh api -X PUT repos/rath/Vimdow/pages -F https_enforced=true
   ```

Optionally verify the domain under Settings → Pages → Verified domains so no
other repository can claim it. There is no `CNAME` file in the site: with
Actions deployment the domain is a repository setting.
