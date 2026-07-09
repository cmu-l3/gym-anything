# Preview on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/preview_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1)

> **See also:** `12_macos_environments.md` for the general macOS env guide
> and `specific_env_notes/safari/notes.md` for the other built-out
> first-party macOS app env.

---

## Install Story: Trivial (after path probe)

Preview is **preinstalled** on every macOS image at
`/System/Applications/Preview.app` — **not** `/Applications/Preview.app`
where you might expect it. Apple has moved its first-party system apps
to `/System/Applications/` since Catalina (Safari is an exception that
still lives in `/Applications/`, presumably for back-compat).

`install_preview.sh` probes both locations and hard-fails only if neither
exists. This is now documented as a general macOS pattern in
`12_macos_environments.md` ("System Apps Live in /System/Applications/").

---

## Preview's Cmd+R Rotation Works End-to-End

Probed live 2026-05 on the use.computer dev fleet (macOS 15.4.1, Preview
12.0):

- `keyboard.hotkey('cmd+r')` and `keyboard.press('r', modifiers=['cmd'])`
  both rotate the front document 90° clockwise (Tools → Rotate Right).
  Screenshot confirms the dice in the test image (the Wikimedia "PNG
  transparency demonstration" 800×600 PNG) visibly rotate; the title bar
  shows `<filename> — Edited`.
- `keyboard.hotkey('cmd+s')` persists the rotation to disk. After save,
  `sips -g pixelWidth -g pixelHeight` reports `pixelWidth=600
  pixelHeight=800` (swapped). The file mtime advances.

**No focus dance needed** — `keyboard.hotkey` reaches Preview even when
macOS notification banners ("Updates Available", "Tips") are visible in
the upper-right. (Earlier suspicion of focus-stealing was incorrect.)

**Re-encoding observation**: input 224566 B → output 293456 B. Preview's
re-encoder chooses different filter/compression params than the source,
but the operation is lossless and `sips` round-trips fine.

---

## `lsappinfo` Pattern: Match the Bundle Path

The Safari-pattern regex `'Safari( |$)'` does NOT match Preview's
lsappinfo entry — Preview has no helper processes with quoted-name
spaces (no "Preview Networking" etc.), so the only line containing
`Preview` followed by a space-or-EOL is missing.

Use `grep -iE 'Preview\\.app'` against `lsappinfo list` instead — that
matches the `bundle path="…/Preview.app"` line, which is emitted exactly
when LaunchServices registers the app.

Documented as a general pattern in `12_macos_environments.md` so future
helper-free apps don't re-discover it.

---

## State Files for Verifier Strategy (Future Tasks)

Prefer file-based verifiers over UI inspection:

| State | Path | Format |
|-------|------|--------|
| Preferences | `~/Library/Preferences/com.apple.Preview.plist` | Binary plist |
| Last opened files | `~/Library/Application Support/Preview/RecentItems.plist` | Binary plist |
| Window state (resume) | `~/Library/Saved Application State/com.apple.Preview.savedState/` | Directory |
| Image cache | `~/Library/Containers/com.apple.Preview/` | (rarely populated; Preview is not as sandboxed as Safari) |

For the image-rotation task we don't read prefs at all — `sips -g pixelWidth -g pixelHeight FILE` is the authoritative signal post-save.

For PDF tasks, use `mdls -name kMDItemNumberOfPages FILE` (Spotlight
metadata) or Python's `pikepdf` / `pypdf` to inspect page count,
annotations, signatures.

---

## Source Image Selection

For dimension-swap-based rotation verification, the source image MUST be
non-square. Wikipedia Commons gotchas:

- **The thumbnail endpoint (`/thumb/.../<size>px-...`) requires an
  explicit `User-Agent`** — curl's default UA returns HTTP 400.
  Wikimedia's robot policy blocks "unsigned" UAs on the upload mirror.
  Set `-A` explicitly. Documented in `setup_task.sh`'s curl call.
- **NASA's Earthrise (square at 2400×2400)** and the Blue Marble
  (close to square) are surprisingly bad choices despite their iconic
  status. Many Apollo-era photos were captured on Hasselblad medium-
  format square film. Probe with a HEAD request + dim inspection before
  committing.
- **The "PNG transparency demonstration" Wikimedia image** is a
  reliable 800×600 PNG with a stable URL and explicit public-domain
  release. It serves the rotation task fine — Preview's PNG round-trip
  preserves dimensions and metadata.

---

## Save Behavior Quirks

- After Cmd+S, Preview's title-bar `— Edited` indicator can persist
  briefly even though the file has been committed to disk. The file on
  disk is the authoritative signal, not the title-bar string.
- Preview does NOT pop a "save as" dialog on Cmd+S for an existing
  on-disk file with a supported format. It saves in place, re-encoding
  if necessary.
- For PDF documents, Cmd+S writes the modified PDF back to the source
  path. Annotations, signatures, and text-box additions all persist.
  This will matter for future PDF-focused tasks.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for window
pgrep -x Preview >/dev/null || open -a Preview "$IMG_PATH"
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qiE 'Preview\.app' && break
  sleep 1
done

# Probe pixel dimensions
/usr/bin/sips -g pixelWidth -g pixelHeight "$FILE"

# Programmatic rotation (sips, command-line equivalent of Cmd+R)
/usr/bin/sips -r 90 "$FILE"

# Cmd+R + Cmd+S via use.computer SDK (Python)
sb.keyboard.hotkey("cmd+r")
time.sleep(2)
sb.keyboard.hotkey("cmd+s")

# Reset for a fresh task
pkill -x Preview
rm -f "$IMG_PATH"
```

---

## Visual Grounding Accuracy (Repeat of safari_env Finding)

Confirmed live 2026-05: `visual_grounding` (Gemini backend) is unreliable
on macOS menu-bar items and small dropdown rows:

- "Where is the Tools menu?" → returned coords for the **Window** menu (one
  to the right). Re-prompting tightened it but still missed by one.
- "Where is Rotate Right?" → returned coords with x outside the dropdown's
  right edge. Click missed the menu entirely.
- The model also returns `"None"` when uncertain instead of a best-guess
  fallback.

This mirrors the same finding documented in `specific_env_notes/safari/`
(Gemini's coords were right for Safari's URL bar at 960,75 but wrong for
the Terminal icon in the Dock). The robust pattern across both envs:

> Ground once → click → screenshot → if the post-action screenshot doesn't
> match the expected state, manually estimate from the screenshot and
> re-click. A single correction usually lands within 1-2 iterations.

For the `rotate_image_clockwise` task this happened twice (Tools menu and
Rotate Right item), each resolved by one manual-estimate retry. See
`evidence_docs/rotate_image_clockwise/interactive_pilot/summary.json` for
the step-by-step trajectory log.

---

## Open Investigations / Future Tasks

- PDF annotation tasks (text boxes, signatures, highlights). State lives
  inside the PDF — verifiable with `pikepdf`.
- Multi-page PDF manipulation (extract page N, delete page N, reorder).
  `pdftk`-style operations are first-class in Preview.
- Image format conversion (PNG → JPEG via Export As…). Cmd+Shift+S opens
  the Export dialog; the format dropdown is in the upper-right of the
  sheet.
- Combining multiple PDFs by dragging thumbnails (challenging — requires
  Preview's sidebar to be visible and precise drag coords).
