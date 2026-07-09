# Safari on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/safari_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1, Safari 18.4)

> **See also:** `12_macos_environments.md` for the general macOS env guide;
> `specific_env_notes/google_earth_macos/notes.md` for the other live env.

---

## Install Story: Trivial

Safari is **preinstalled** on every macOS image at `/Applications/Safari.app`. The base-macos sandbox ships Safari 18.4. `install_safari.sh` only verifies the bundle is present (hard-fails otherwise) and dumps the version — no DMG, no Rosetta, no brew.

This makes safari_env's reset much faster than google_earth_env: ~15-20s on a warm sandbox vs ~70s for Google Earth.

---

## Configuration Story: `defaults write com.apple.Safari`

All Safari preferences live in `com.apple.Safari` (visible via `defaults read com.apple.Safari`). Useful keys observed in setup_safari.sh:

| Key | Type | Purpose |
|---|---|---|
| `IncludeDevelopMenu` | bool | Enables the Develop menu (needed for Web Inspector) |
| `WebKitDeveloperExtras` / `WebKitPreferences.developerExtrasEnabled` | bool | Older keys; safe to set in tandem |
| `HomePage` | string | Set to `about:blank` for deterministic startup |
| `NewWindowBehavior` / `NewTabBehavior` | int | 1 = open homepage, 0 = empty, 2 = top sites, etc. |
| `AlwaysRestoreSessionAtLaunch` | bool | False to avoid restoring previous session |
| `ShowFavoritesBar` | bool | Bookmarks bar (visible) |
| `ShowFullURLInSmartSearchField` | bool | Show full URL in address bar (needed for verifiers) |
| `SendDoNotTrackHTTPHeader` | bool | DNT header |
| `WarnAboutFraudulentWebsites` | bool | Safe browsing |
| `SuppressSearchSuggestions` | bool | Quieter address bar |

State files Safari reads/writes (verifier-friendly):

| File | Format | What's in it |
|---|---|---|
| `~/Library/Safari/Bookmarks.plist` | Binary plist | Bookmarks tree (Favorites bar, Bookmarks menu, custom folders). Read with `plistlib`. |
| `~/Library/Safari/History.db` | SQLite | URL history (table `history_items`, `history_visits`) |
| `~/Library/Safari/Downloads.plist` | Binary plist | Download manifest |
| `~/Library/Safari/ReadingList.plist` | Binary plist | Reading List entries |
| `~/Library/Safari/LastSession.plist` | Binary plist | Last open tabs (used on restore) |
| `~/Library/Safari/PerSitePreferences.db` | SQLite | Per-site permissions (cookies, location, camera, etc.) |
| `~/Library/Preferences/com.apple.Safari.plist` | Binary plist | The `defaults` domain itself |

For verifiers, prefer these files over UI inspection — they're deterministic, programmatic, and don't need AX over SSH (TCC trap from `12_macos_environments.md`).

---

## Known Gotchas

### `IncludeDevelopMenu` write does NOT show up in the menu bar — root cause unknown
**Symptom:** `defaults write com.apple.Safari IncludeDevelopMenu -bool true` succeeds (verifiable with `defaults read`), but Safari's Develop menu is never visible in the menu bar.

**Investigated approaches that all FAILED** (probed live 2026-05 against use.computer dev fleet — see `evidence_docs/devtools_security_header_audit/probe_prefs/` for screenshots):

| Variant | Approach | Develop menu visible? |
|---|---|---|
| A | `defaults write com.apple.Safari … + killall cfprefsd + open -a Safari` | ❌ |
| B | `defaults write -app Safari …` (CFPreferencesAppValueSet form) + killall + open | ❌ |
| C | `PlistBuddy` on `~/Library/Preferences/com.apple.Safari.plist` | ❌ (and revealed the sandbox path — see below) |
| D | `killall cfprefsd` FIRST, then write, then open | ❌ |
| E1 | `defaults write` to the sandbox container path | ❌ |
| E2 | `PlistBuddy` on the container path | ❌ |
| E3 | Write to BOTH standard and container paths | ❌ |

**Real Safari prefs location**: variant C surfaced a critical clue. `defaults read` against `~/Library/Preferences/com.apple.Safari` reports `1` for `IncludeDevelopMenu` (because we wrote it there), but Safari is **sandboxed** and actually reads from:

```
~/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari.plist
```

This was revealed by PlistBuddy's error message in variant C: `The domain/default pair of (/Users/lume/Library/Containers/com.apple.Safari/Data/Library/Preferences/com.apple.Safari, IncludeDevelopMenu) does not exist`.

**But** — writing the pref to the container path also doesn't enable Develop menu (variants E1/E2/E3). So the issue is not just sandbox-path mismapping. Some Safari preferences (likely a security-relevant subset including `IncludeDevelopMenu` and probably `ShowFavoritesBar`) require an additional context — a user gesture in System Settings, an entitlement, or a profile-managed configuration — that bare `defaults write` doesn't satisfy.

**Practical workaround for tasks**: agents don't strictly need the Develop menu visible — they can:
- Hit `Cmd+Option+I` (Web Inspector keyboard shortcut), which may still work if the underlying entitlement is set even when the menu is hidden.
- Use Terminal (`curl -I https://example.com/`) to inspect HTTP headers.
- Use AppleScript `do shell script` from within an osascript invocation.

For the `devtools_security_header_audit` task port, the simulator in `collect_evidence.py` uses curl and the verifier scored 97/100 — proving the task is completable without the menu.

**Open investigation**: not blocking task development, but worth solving — likely requires either an MDM profile manifest, a manual System Settings toggle that we capture and replay, or a `defaults write` with a key Apple hasn't documented publicly.

### `pgrep -f "/Applications/Safari.app"` matches helpers, not main Safari
**Symptom:** `pgrep -f "/Applications/Safari.app"` returns matches even when Safari itself isn't running — because helpers like `SafariLinkExtension`, `SafariWidgetExtension`, etc. live under that bundle path and may be running for the OS shell.

**Fix:** use `pgrep -x Safari` (exact process-name match). The main Safari binary's process name is exactly `Safari`. Helpers are named `SafariLinkExtension`, `SafariWidgetExtension`, etc. — `-x` excludes them.

Both `setup_task.sh` (idempotent launch check) and `verifier.py` (presence check) use `pgrep -x Safari`.

### `lsappinfo list` shows helpers separately
After `open -a Safari`, `lsappinfo list` shows:
- "Safari" (main app)
- "Safari Networking", "Safari Graphics and Media", "Safari Web Content (Prewarmed)" (helpers)

Verifiers should grep for `Safari( |$)` (word-boundary) rather than just `Safari` so the count isn't inflated by helpers when checking single-app presence. The launch_safari verifier uses `grep -iE 'Safari( |$)'`.

---

## End-to-End Verification (live, dev sandbox, 2026-05)

```
reset() took 15.6s on a warm sandbox (47.8s on the first cold-ish run)
pre_start (install_safari.sh):  ~1s   (no install, just verify)
post_start (setup_safari.sh):   ~2s
pre_task (setup_task.sh):       ~3-5s (open + lsappinfo poll)
verifier: passed=True, score=100
```

Visual evidence:
- `evidence/launch_safari_panel_view.png` — what the noVNC viewer shows at the moment the interactive panel appears (Safari open, menu bar active, address bar focused).
- `evidence/launch_safari_final.png` — final frame captured after `step(mark_done=True)`.

Both screenshots confirm Safari is running with the expected start state.

---

## What to Watch For When Porting Tasks

1. **Bookmark verifiers** — parse `~/Library/Safari/Bookmarks.plist` with `plistlib.load(open(path, "rb"))`. Top-level is a dict; folders are dicts with key `WebBookmarkTypeList`, leaf bookmarks are dicts with `WebBookmarkTypeLeaf` and `URLString`. Pre-create a known starting bookmark tree in setup_task.sh so the verifier can compute deltas.

2. **History verifiers** — query `~/Library/Safari/History.db` (SQLite). Tables: `history_items` (`url`, `domain_expansion`, `visit_count`), `history_visits` (`history_item`, `visit_time`). Visit times are Mac absolute time (seconds since 2001-01-01 UTC) — convert to epoch with `+ 978307200`.

3. **Download verifiers** — check `~/Downloads/<filename>` directly (file existence + size). The `Downloads.plist` manifest is only updated when downloads are actively managed via the Downloads UI.

4. **Site permissions** — query `~/Library/Safari/PerSitePreferences.db` (SQLite). Cookie acceptance, location, camera, etc. are per-domain rows.

5. **Privacy hardening** — most prefs are in `com.apple.Safari` (`SendDoNotTrackHTTPHeader`, `WarnAboutFraudulentWebsites`, `SearchProviderShortNamePreference`). Cross-site tracking prevention is `WebKitPreferences.privateBrowsingEnabled` (private mode) and `WebKitStorageBlockingPolicy`.

6. **DevTools tasks** — MUST `killall cfprefsd` after the `defaults write IncludeDevelopMenu` in setup_task.sh, or the agent won't be able to open Web Inspector. The View > Show Web Inspector menu / `Cmd+Option+I` shortcut requires Develop menu enabled.

7. **`open -a Safari "https://example.com"`** opens a URL in a new Safari window from the command line — useful for pre_task to position Safari on a specific page before the agent acts. AppleScript also works: `osascript -e 'tell application "Safari" to open location "https://example.com"'`.

---

## Quick-Reference Commands

```bash
# Launch idempotently and wait for window
pgrep -x Safari >/dev/null || open -a Safari
for i in $(seq 1 30); do
  /usr/bin/lsappinfo list 2>/dev/null | grep -qi "Safari( |$)" && break
  sleep 1
done

# Open a URL
open -a Safari "https://example.com"

# Read a pref
defaults read com.apple.Safari HomePage

# Inspect bookmarks
python3 -c "import plistlib; print(plistlib.load(open('/Users/lume/Library/Safari/Bookmarks.plist','rb')))"

# Inspect history
sqlite3 /Users/lume/Library/Safari/History.db "SELECT url, visit_count FROM history_items ORDER BY visit_count DESC LIMIT 20"

# Reset for a fresh task
rm -f /Users/lume/Library/Safari/{Bookmarks.plist,History.db,LastSession.plist,ReadingList.plist}
defaults delete com.apple.Safari 2>/dev/null || true
```
