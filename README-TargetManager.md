# TargetManager.au3 — setup & usage

## What changed

The earlier version tried to drive Chrome through the whole compile
process automatically — clicking the upload area, clicking Start, catching
the download dialog. That turned out to be the wrong thing to automate:
screen coordinates went stale as soon as the page layout shifted, and
there was no clean way to detect "compile finished" without extra
libraries. None of that was actually the hard part of this problem.

The hard part was always just: how do you guarantee trigger images upload
in the same order every time, including after you add new ones later?
This version solves exactly that, and leaves the actual dragging, Start
click, and download to you — which was never the annoying part anyway.

**I could not run or test this script myself** — AutoIt only runs on
Windows and this session doesn't have a Windows machine — but it's a much
simpler script now (pure file renaming, an ini file, and text substitution
in index.html — no browser automation, no screen coordinates, no timing
guesses), so there's a lot less that can go subtly wrong.

## How order is guaranteed

Every file in `targets/` gets a zero-padded number prefix: `01_`, `02_`,
and so on. Windows sorts filenames alphabetically, and a zero-padded
numeric prefix sorts exactly the way you'd expect (01, 02, ... 10, 11 —
not 1, 10, 11, 2). So whenever you select all files in `targets/` and drag
them into the compile tool, they always land in prefix order — which is
also the exact order the script uses to write `targetIndex` values into
`index.html`.

New trigger images just get the next available number. Existing prefixed
files are never renamed or renumbered, so adding one more target never
shifts around the indexes (and hand-tuned scale/position) of the ones you
already set up.

## One-time setup

1. Install AutoIt3 from https://www.autoitscript.com/ if you don't have it.
2. Put `TargetManager.au3` in your project folder:
   `C:\Users\house\OneDrive\Documents\GitHub\householderc-testAR\`
3. Just run it. No extra AutoIt libraries needed — everything it uses
   (`Array.au3`, `File.au3`, `Math.au3`, `GDIPlus.au3`, GUI includes) ships
   with a standard AutoIt install.

## What happens each run

1. Scans `targets/`. Any file without a `NN_` prefix is treated as new and
   gets renamed with the next available number (e.g. `frontdoor.png` →
   `03_frontdoor.png`). You'll see a summary of any renames.
2. Opens a **Manage Targets** list showing every current target and its
   assigned overlay (or "NOT SET" if it isn't configured yet). Select any
   one and click **Edit Selected** to reopen the config GUI for it,
   pre-filled with its current overlay/position/rotation/scale — this is
   how you change something without hand-editing `index.html`. You can
   edit as many as you want. Click **Continue** when you're done; it won't
   let you continue while anything is still "NOT SET".
3. Shows you the final order and asks you to confirm before touching
   `index.html`.
4. Backs up the current `targets.mind` and `index.html` into `backups/`.
5. Rewrites `index.html` between the `<!-- AUTOGEN:... -->` markers to
   match the current file order — everything else in the file is left
   alone.
6. Opens the compile tool in your browser and opens the `targets/` folder
   in Explorer, so you can immediately press Ctrl+A and drag everything
   in. From there it's the same manual process as before: Start, wait,
   Download compiled, save over `targets.mind`.

## Editing an existing target

Just run the script — even with nothing new in `targets/`, it'll still
open the Manage Targets list. Pick the target, click Edit Selected, change
whatever you want (swap the overlay, tweak position/scale/rotation),
Save, then Continue. `index.html` gets rewritten with the new values.
Closing the small edit window without saving just returns you to the list
with nothing changed — only closing the Manage Targets window itself
cancels the whole run.

## Previewing placement without a camera

Every Edit/Configure window now has a **Preview (no camera)** button next
to Save. Click it any time — even before you've saved — and it opens
`preview.html` in your browser: a plain 3D scene (no MindAR, no camera
permission) showing the trigger image as a flat panel with the overlay
sitting on it using whatever position/rotation/scale/width/height values
are currently in the form. Drag to look around, WASD to move closer or
farther away.

This works because the overlay's placement relative to the marker never
actually depends on the camera — MindAR only decides where to put the
*virtual camera*, not where the overlay sits on the target. So this preview
is a faithful stand-in for tuning position/scale/rotation, just not for
tracking quality (how fast/reliably MindAR locks onto that image), which
still needs a real test on the phone.

Change a value, click Preview again (or just refresh the browser tab) to
see the update — nothing needs to be saved first. `preview.html` gets
overwritten each time you click Preview, so don't rename or keep copies of
it; it's a scratch file, not something to check in.

**Why it opens `http://localhost:8791/...` instead of just double-clicking
the file:** Chrome (and most browsers) will display a local image just
fine, but refuses to let WebGL use a `file://` image as a texture at all —
you'd see a flat, untextured gray box instead of the actual picture, even
though the image "loaded" correctly. A real server makes everything
same-origin and that restriction goes away, so clicking Preview now starts
a tiny local static file server for you automatically (serving your project
folder) instead of asking you to remember to run one by hand. It shows up
as a minimized window titled **"MindAR Preview Server (closing this window
stops it)"** — leave it running for as long as you're tuning placement,
close it whenever you're done. If you click Preview again later and it's
already running, it's reused rather than starting a second one.

If it ever fails to start (e.g. something already using that port, or a
locked-down PowerShell execution policy), you'll get a message with a
manual fallback: run `python -m http.server 8791` in the project folder
yourself, then click Preview again.

The preview page also checks its own two images as soon as it loads. If
either one genuinely fails to load (wrong filename, moved file, etc.) a red
banner appears on the page telling you which one and what path it tried —
so a blank/missing overlay always explains itself instead of just being an
empty gap on screen. The info box in the top-left also prints the exact
overlay/position/rotation/scale/width/height it's using, so you can compare
against what's in the edit window.

## Version number auto-increment

The `Revela Occulta vX.Y` text on the start button gets its minor version
bumped by 1 every time the script rewrites `index.html` — v1.1 becomes v1.2,
then v1.3, and so on. There's no cap or rollover into the major number; it
just counts up. This happens automatically on every run that reaches the
index.html rewrite step (including edit-only runs where you didn't add any
new targets), so you always have a quick visual confirmation on the page
itself that you're looking at the latest build. If you ever need to reset
or jump the version, just hand-edit the number in `index.html` once — the
script will keep incrementing from whatever it finds next time.

## First run note

Your 6 existing images have no prefix yet, so the first run will rename
all of them in their current alphabetical order and, since
`target-settings.ini` already has entries for them from earlier testing,
shouldn't need to ask you to reconfigure anything — just the renaming
step and the index.html rewrite.

## Files this creates in your project folder

- `target-settings.ini` — per-trigger-image settings (overlay, position,
  rotation, scale). Keyed by filename with the order-prefix stripped, so
  it's unaffected by renaming.
- `backups/` — timestamped copies of `targets.mind` and `index.html` from
  before each run.
- `preview.html` — scratch file for the camera-free placement preview,
  overwritten every time you click Preview. Safe to ignore/delete; it's
  regenerated whenever you need it.
- A small PowerShell server script in your Windows temp folder (not in the
  project folder), used to serve the preview locally. You'll never need to
  touch it directly.

## Large trigger images

A few of your files are 10-12MB. That'll make the manual compile step
noticeably slower than it needs to be — MindAR's guidance is about
contrast and lighting, not raw resolution. Downsizing to roughly
1500-2000px on the long edge before compiling would likely speed things up
without hurting tracking quality.
