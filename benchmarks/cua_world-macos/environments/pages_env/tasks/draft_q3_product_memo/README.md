# draft_q3_product_memo

Apple Pages document-creation task. The agent drafts a 3-priority Q3 product
strategy memo and saves it under `~/Documents/`.

## Domain context

A product manager prepping their Q3 strategy memo would type a bullet-list of
priority items into Pages, then save with a descriptive filename. The task
verifies the agent can:

1. Use Pages's UI to create a new blank document (the env's pre_task does
   this via AppleScript, so the agent starts on a blank page \u2014 no template
   chooser handling required).
2. Type multi-line content with specific phrases (verifier checks exact tokens
   like `2026-09-30` and `NPS from 42 to 55`).
3. Execute a save-as flow (File \u2192 Save... or Cmd-S, then type the filename,
   navigate to Documents, click Save).

## Required body content

Three priority lines (bulleted or plain text both accepted):

1. `Launch AI-assisted onboarding by 2026-09-30`
2. `Raise NPS from 42 to 55 with quarterly user-research sprints`
3. `Reduce P0 incident rate by 30% via on-call rotation overhaul`

## Required save destination

`/Users/lume/Documents/Q3 Product Strategy Memo.pages`

Apple Pages saves to `.pages` packages (directory bundles in modern Pages 14+,
single-file zips in Pages-09 format). The verifier accepts both shapes.

## How the result is captured

`export_result.sh` does three things:

1. **Filesystem check** \u2014 does `/Users/lume/Documents/Q3 Product Strategy Memo.pages`
   exist and was it modified after `task_start`?
2. **AppleScript queries** \u2014 `tell application "Pages" to return body text of
   document "Q3 Product Strategy Memo"` (and a `front document` fallback). This
   reads body text from the live app, which works over SSH because we're
   talking directly to the app (per `12_macos_environments.md`).
3. **Bundle string-scan fallback** \u2014 if both AppleScript reads come back
   empty but the file exists, run `strings` over the .pages bundle's index
   files. Useful when the agent saved-and-closed the document.

It writes `/tmp/draft_q3_product_memo_result.json` with:

- `target_exists`, `target_mtime`, `target_fresh` \u2014 filesystem signal
- `body_text_target` / `body_text_front` \u2014 AppleScript signal
- `phrase_ai`, `phrase_date`, `phrase_nps`, `phrase_p0` \u2014 boolean phrase flags
- `total_pages_post_start` / `other_post_start_pages` \u2014 wrong-target signal

If `target_exists == False` AND other `.pages` files were saved after
`task_start`, the verifier classifies as wrong-target and returns 0 regardless
of body content (Pattern #2 in `03_verification_patterns.md`).

## Scoring (100 pts, pass at 60)

| Criterion | Points | What |
|-----------|-------:|------|
| C1 | 20 | File saved at `/Users/lume/Documents/Q3 Product Strategy Memo.pages` with mtime > task_start (partial 10 if stale-mtime) |
| C2 | 25 | Body contains `AI-assisted onboarding` (case-insensitive) |
| C3 | 25 | Body contains `2026-09-30` |
| C4 | 30 | Body contains `NPS from 42 to 55` AND `P0 incident rate` + `30%` (split 15+15) |

**Smallest passing combination:**
- C1 (fresh) + C2 + C3 = 70 PASS
- C1 (fresh) + C2 + C4-half (NPS) = 60 PASS (boundary)
- C1 (fresh) + C2 alone = 45 FAIL

**Anti-Pattern #4 partial-credit safety check** (no full pass via partials):
- Without C1, gates fire \u2192 0 regardless of content.
- With C1 + half of C4 only = 35.
- Worst-case stale-fresh partial: 10 + 25 + 25 + 30 = 90 (intentional: the body
  is clearly the agent's work; stale mtime is a clock-skew edge case).

## Anti-gaming protections

- **Do-nothing**: `target_exists == False AND total_pages_post_start == 0` \u2192 0.
- **Wrong-target**: agent saved with the wrong filename \u2192 0.
- **Content-no-save**: agent typed all the right phrases into an unsaved Pages
  document. `front document` query reads them, BUT the do-nothing gate fires
  (`total_pages_post_start == 0`) and zeros everything. This is intentional:
  the task explicitly requires saving the document.
- **Pre-existing file**: `setup_task.sh` deletes the target path before launch
  AND records a pre-snapshot of all `~/Documents/*.pages` files with their
  mtimes. Anything matching the target path AND `mtime > task_start` is
  guaranteed to be agent-produced (per pattern #6 in `10_cross_cutting_patterns.md`).
- **Stale-mtime fallback (10 pts on C1)**: deliberate concession for clock-skew
  edge cases where the target file exists with all the right content but its
  mtime predates task_start. The body content makes this almost certainly the
  agent's work; awarding 10 pts (not 20) on C1 retains a meaningful signal.

## Edge cases

- **Pages 09 vs modern format**: modern Pages writes `.pages` as a package
  directory; older saves used a single-file zip. The verifier's `target_exists`
  accepts both (`isdir OR isfile`).
- **Save dialog**: Pages on first save shows a Save Dialog (filename + folder
  picker). The agent must type the filename and navigate to Documents. The
  task description specifies the full path explicitly.
- **Autocorrect**: `setup_pages.sh` disables global text-substitution
  (`NSAutomaticDashSubstitutionEnabled`, `NSAutomaticTextReplacementEnabled`,
  etc.) so Pages doesn't rewrite `30%` or `42 to 55` before the verifier
  reads them back.
- **Upgrade modal**: `setup_pages.sh` sets the `TMAApplicationUpdateNotifier.*`
  keys to high values so the "New Version of Pages Available" alert doesn't
  appear and block the document area. Without this suppression, the agent
  would have to dismiss the modal first.
