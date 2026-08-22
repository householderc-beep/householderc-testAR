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

## Large trigger images

A few of your files are 10-12MB. That'll make the manual compile step
noticeably slower than it needs to be — MindAR's guidance is about
contrast and lighting, not raw resolution. Downsizing to roughly
1500-2000px on the long edge before compiling would likely speed things up
without hurting tracking quality.
