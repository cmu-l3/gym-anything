# `play_target_audio_clip` — domain context, schema, edge cases

## What the task is

QuickTime Player is launched with a small audio file already loaded and
paused at 0:00. The agent's single responsibility is to start playback and
let the audio play past the 1.0-second mark.

The audio file is `~/Documents/qtp_target_audio.aiff`, a copy of the macOS
system sound `/System/Library/Sounds/Funk.aiff` (~2.16 seconds, AIFF, 48 kHz
24-bit stereo). It is staged fresh on every `pre_task` so file mtime is the
task-start baseline and no state from a previous reset can bleed through.

The natural agent action is one keystroke: press `Space`. QuickTime's
default key binding for the space bar is "Play/Pause Movie" — pressing it
once starts playback at 1× rate from current_time = 0.0, and the audio
naturally finishes at ~2.16 s without further input.

## Why this task is meaningful

It exercises the most common QuickTime user gesture (start playback) against
a verifiable surface that doesn't require AX over SSH (which is TCC-blocked
in the use.computer base-macos sandbox per
`12_macos_environments.md`):

> QuickTime Player publishes a rich AppleScript scripting interface (its
> `.sdef`) that exposes `documents`, `current time`, `duration`, `playing`,
> and `file` properties. These are queryable from `osascript` over SSH
> without any TCC issues — the scripting goes through Apple Events directly
> to the QuickTime process, NOT through `System Events`. (Verified live
> 2026-05-17: `osascript -e 'tell application "QuickTime Player" to get
> current time of front document'` returns the live position number even
> when called by `lume` over `sshd-keygen-wrapper`.)

## Schema — `export_result.sh` output

The post_task hook writes `/tmp/play_target_audio_clip_result.json` with
the following keys (all snake_case, no nested objects):

| Key | Type | Source | Notes |
|---|---|---|---|
| `task_start` | int | `/tmp/task_start_timestamp` | Unix epoch seconds, set by setup_task.sh |
| `documents_open_count` | int | AppleScript `count of documents` | 0 when no document loaded |
| `front_document_name` | str | AppleScript `name of front document` | empty when docs == 0 |
| `front_document_path` | str | AppleScript `POSIX path of (file of front document as alias)` | empty when docs == 0 or for in-memory recordings |
| `front_document_duration` | float | AppleScript `duration of front document` | seconds; matches the file's audio duration |
| `front_document_current_time` | float | AppleScript `current time of front document` | seconds; the primary signal |
| `front_document_playing` | bool | AppleScript `playing of front document` | secondary signal; not used in scoring |
| `target_file_exists` | bool | `stat -f` on the target path | |
| `target_file_mtime` | int | `stat -f %m` | Unix epoch seconds |
| `target_file_size` | int | `stat -f %z` | bytes |
| `target_file_unchanged` | bool | `target_file_size == 623130` | strict size match |
| `process_running` | bool | `pgrep -x 'QuickTime Player'` | crash detector |

## Scoring — 100 points, pass at 60

| Criterion | Pts | Condition |
|---|---|---|
| C1 front_document_match | 15 | `front_document_name == "qtp_target_audio.aiff"`. **Strict gate** — failure here returns score=0 without scoring others (Pattern #2). |
| C2 target_file_integrity | 10 | `target_file_exists AND target_file_unchanged` |
| C3 playback_started | 40 | `current_time >= 0.5` (binary) |
| C4 meaningful_playback | 30 | `current_time >= 1.0` (binary) |
| C5 process_alive | 5  | `process_running` |

### Why the thresholds

- **C3 at 0.5 s**: catches any non-trivial Space-press playback. Press-and-
  release of the spacebar in the QuickTime SDK loop adds ~50–100 ms of
  startup before the audio actually begins moving the playhead, so a
  threshold below 0.3 s would risk false positives from incidental key
  noise. 0.5 s is well above that floor.
- **C4 at 1.0 s**: requires the agent to let playback proceed for an
  observable duration. If the agent presses Space and immediately presses
  it again (toggle off), `current_time` typically lands between 0.05 and
  0.3 s — below 1.0 s. So C4 is gated on real, sustained playback.
- **Partial-only max**: 15 + 10 + 0 + 0 + 5 = 30. Pass threshold 60 > 30 ✓
  (Anti-Pattern #4 from `task_creation_notes/14_task_design_antipatterns.md`).

## Anti-gaming strategies considered

| Strategy | Defended? | How |
|---|---|---|
| Do nothing (file loaded but never played) | Yes | C3+C4 = 0, max attainable = 30 < 60 |
| Open a different file as front document | Yes | Strict C1 gate → score 0 |
| Close the QuickTime document | Yes | Strict gate (`docs_open == 0`) → score 0 |
| Quit QuickTime entirely | Yes | Same strict gate; also C5 fails |
| Modify the file on disk to be longer/different | Mostly | C2 fails (size mismatch). C3/C4 still scoreable if the agent actually played, but feedback flags the file mismatch. |
| Use AppleScript to set `current time` directly without playing | Marginal | Sets `current_time`, would pass C3/C4. We accept this — it's still "the agent caused playback state to advance", which is the spirit of the task. (Could be hardened by also checking `playing` was ever true via a watcher script in pre_task, but adds complexity for minimal gain.) |
| Replace `/System/Library/Sounds/Funk.aiff` itself | No | OS-level mutation; out of scope for agent behavior in a sandbox |

## Live timing

| Phase | Time |
|---|---|
| pre_task (kill QT + stage file + open + register + settle) | ~7 s |
| Agent action (single space-press) | <1 s |
| Settle (let audio play ~2.5 s) | ~2.5 s |
| post_task (AppleScript probe + stat + JSON emit) | ~2 s |

The full task usually completes in under 15 s on a warm sandbox.

## Edge cases

- **AppleScript returns `0.0` for a brand-new document for a brief window**
  before the first playback event fires. setup_task.sh sleeps 3 s after
  opening the file so this race is closed before the agent gets control.
- **Pressing Space when QuickTime is not the front app** does nothing. The
  pre_task `open -a` brings QuickTime to the front; agents that click off
  to another window must click back before pressing Space. This is normal
  macOS behavior and not specific to our env.
- **The audio file is a system asset.** It is not modifiable per Apple's
  signed-system-volume policy. We always copy it to `~/Documents/` so the
  target path is writeable for adversarial test scenarios that try to
  truncate or replace it.
