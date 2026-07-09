# Task: Preview — Rotate Image 90° Clockwise & Save In Place

**Difficulty:** easy
**App:** Apple Preview (`/Applications/Preview.app`) on macOS via use.computer

## Domain Context

The single most common image-editing operation a non-designer reaches for
Preview to do is rotation: a phone photo arrived sideways, a scan came out
landscape, a screenshot needs to be portrait for a slide. Preview ships
1-shortcut rotation (⌘R clockwise / ⌘L counter-clockwise) and "save in
place" with ⌘S. This task validates that an agent can drive that 30-second
real-world workflow end-to-end through Preview's GUI.

## Goal

Open the image at `~/Documents/preview_rotation_input.png` in Preview,
rotate it 90° clockwise, and save the result **in place** at the same path so
the file on disk is the rotated version. Do not rename, do not export to a
different format, and do not modify any other file in `~/Documents`.

## Source Image

- **Image**: Wikimedia Commons "PNG transparency demonstration" — a
  reference 800×600 PNG used in the PNG specification to illustrate
  alpha-channel handling.
- **URL**: `https://upload.wikimedia.org/wikipedia/commons/4/47/PNG_transparency_demonstration_1.png`
- **License**: Released to the public domain by the author (Pierre-Yves
  Lapersonne). Sourced via Wikimedia Commons.
- **Dimensions**: 800 × 600 px. Setup records actual dimensions via `sips`
  so a future Wikimedia rebuild that changes the exact pixel count won't
  break the verifier — the rotation check is `(cur_w, cur_h) ==
  (init_h, init_w)`.

**Earlier candidates rejected** (probed live 2026-05): NASA's Earthrise
thumbnail on Wikimedia (`/thumb/.../640px-...jpg`) returns HTTP 400
without a custom `User-Agent` (Wikimedia's robot policy); the full-res
original is 2400×2400 (square) so rotation is undetectable by dimension
swap. The PNG transparency demonstration avoids both issues.

A fallback URL (the legacy `wikipedia/en` mirror of the same file) is
hard-coded into `setup_task.sh` per env-creation pattern #7. Both URLs
require an explicit `User-Agent` — set in the curl call.

## Verification Strategy (4 criteria, 100 pts, pass at 70)

| # | Criterion | Pts |
|---|---|---|
| 1 | Input file present at expected path | 15 (binary) |
| 2 | File mtime > task_start (re-saved during task) | 25 (binary) |
| 3 | (width, height) post-action == (height, width) pre-action — 90° rotation signature | 40 (binary) |
| 4 | `sips` can still decode the file as an image (no corrupted save) | 20 (binary) |

**Partial-credit safety check (Anti-Pattern #4):** worst-case partial-only
score is `15 + 25 + 0 + 20 = 60` (the "agent saved the file without rotating
it" case). Pass threshold 70 is strictly greater → only an agent that
genuinely rotated AND saved can pass.

**Anti-gaming gates** (return score=0 immediately):

- **No-work gate**: `NOT input_fresh AND NOT dimensions_swapped`. Catches
  do-nothing (file inherits setup-time mtime, dimensions unchanged) and
  wrong-target (agent rotated some other file, canonical untouched). Per
  Pattern #2 in `03_verification_patterns.md`.
- **Setup-failure gate**: `initial_width == 0`. `setup_task.sh` exits if
  the source image is square or unreadable, but a defensive verifier
  returns 0 in case export ever sees a sentinel-zero baseline.

**Strategy enumeration table** (verified offline by `test_verifier_offline.py`):

| Strategy | C1 | C2 | C3 | C4 | Total | Pass? |
|---|---|---|---|---|---|---|
| Do-nothing                       | 0  | 0  | 0  | 0  | 0   | No  |
| Wrong-target (rotated other file)| 0  | 0  | 0  | 0  | 0   | No  |
| Saved without rotating           | 15 | 25 | 0  | 20 | 60  | No  |
| Rotated + saved (happy path)     | 15 | 25 | 40 | 20 | 100 | Yes |
| Rotated externally, backdated    | 15 | 0  | 40 | 20 | 75  | Yes |
| Deleted the file                 | 0  | 0  | 0  | 0  | 0   | No  |
| Setup baseline missing           | 0  | 0  | 0  | 0  | 0   | No  |

## Setup / Export Pipeline

- **setup_task.sh**:
  1. Force-quits any running Preview.
  2. Deletes any stale `~/Documents/preview_rotation_input.png`.
  3. Downloads the canonical source image from Wikimedia Commons (with one
     fallback URL).
  4. Records pixel dimensions via `sips -g pixelWidth -g pixelHeight` and
     writes them to `/tmp/preview_rotate_initial_dims.json` along with the
     initial SHA-256. Hard-fails if the source is square (rotation
     undetectable).
  5. Sleeps 2 s, then writes `/tmp/preview_rotate_task_start_timestamp`
     (Unix epoch) so any subsequent Cmd+S strictly produces `mtime > task_start`.
  6. Launches Preview with the image loaded so the agent sees a known
     start state without having to navigate File→Open.

- **export_result.sh**:
  1. Captures a screenshot for the trajectory archive.
  2. Quits Preview so any buffered "edited" autosave flushes to disk.
  3. Reads `sips` dimensions, file mtime, file size, and SHA-256 of the
     canonical path post-action.
  4. Computes `dimensions_swapped` (current dims == initial dims swapped).
  5. Computes `byte_content_changed` (sha256 differs from baseline) as an
     ancillary signal.
  6. Emits `/tmp/rotate_image_clockwise_result.json`.

## Live Behavior Notes (macOS / Preview)

- Preview's File menu writes the in-memory representation back to the
  source path on ⌘S, re-encoding the PNG. The output is pixel-identical
  but the byte content changes because Preview's encoder picks different
  filter/compression parameters than the original Wikimedia upload
  (lossless re-encode, so dimensions are preserved). The SHA-256 differs
  as a result, so `byte_content_changed` is exported but not used for
  scoring — it would pass for "saved without rotating".
- `sips -r 90` from Terminal rotates an image in place and updates mtime;
  if an agent realises Preview is overkill for this task, the verifier
  doesn't penalise the shortcut — but the task description specifically
  asks for Preview, and a live trajectory should drive the GUI.
- Preview does NOT enforce save-on-quit prompts when the file is on disk
  and ⌘S has been pressed; if the agent rotates but does NOT press ⌘S,
  Preview's `quit` command will silently discard the rotation. The
  export's `pkill -x Preview` step mimics this — guaranteeing the verifier
  measures only what was actually written to disk.
- The Save shortcut is **⌘S**, NOT ⌘+Return. There is no Preview-specific
  Enter≠Return trap (unlike Safari's address bar — see
  `12_macos_environments.md`).

## Why This Is `easy`, Not `medium`

The task description explicitly names the file, the operation, and the
keyboard shortcut. The agent doesn't have to discover what to rotate,
which direction, or which file to save. Per
`01_core_principles.md` § Principle 5 / Complexity Spectrum, that
combination is `easy`. A future medium-or-above Preview task could
require the agent to *discover* which image needs rotation (e.g., "this
gallery contains one sideways photo — fix it") or chain rotation with
annotation, signature, and PDF export.
