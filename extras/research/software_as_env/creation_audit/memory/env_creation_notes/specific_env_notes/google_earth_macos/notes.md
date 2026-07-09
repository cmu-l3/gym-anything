# Google Earth Pro on macOS — Lessons Learned

Environment: `benchmarks/cua_world-macos/environments/google_earth_env/`
Runner: `UseComputerRunner` (use.computer dev fleet, M4 macOS 15.4.1)

> **See also:** `12_macos_environments.md` for the general macOS env guide,
> and `specific_env_notes/google_earth/` for the older Linux version's lessons
> (most of the *application* behavior — first-run dialogs, KML state, navigation
> quirks — carries over; only the install path is platform-specific).

---

## Install Path (working as of 2026-05)

**DMG URL that works:** `https://dl.google.com/earth/client/advanced/current/GoogleEarthProMac-Intel.dmg`

URLs that **do NOT** work (404s probed live 2026-05):

| URL | Status |
|-----|--------|
| `…/earth/client/advanced/current/GoogleEarthProMac.dmg` | 404 |
| `…/dl/earth/client/advanced/current/GoogleEarthProMac.dmg` | 404 |
| `…/dl/earth/client/advanced/current/GoogleEarthProMac-Intel.dmg` | 200 (also works) |

Many older blog posts and the Linux google_earth notes reference the non-`-Intel` URL. Don't trust documentation — probe before relying.

**Shape of the DMG (changed!):** Google migrated the Mac distribution from a drag-and-drop `.app` bundle to a `.pkg` installer. Don't `ditto` — use `installer -pkg`:

```bash
MOUNT_POINT=$(hdiutil attach -nobrowse -readonly "$DMG_PATH" \
              | awk -F'\t' '$NF ~ /^\/Volumes\// {print $NF}' | tail -1)
PKG=$(find "$MOUNT_POINT" -maxdepth 2 -name "Install Google Earth*.pkg" -type f | head -1)
sudo installer -pkg "$PKG" -target /
hdiutil detach "$MOUNT_POINT" -force
```

The DMG also contains `Google Earth Update Helper.app` — ignore it. The real app is created by the .pkg at `/Applications/Google Earth Pro.app`.

**Defensive install:** detect both shapes (find for `.pkg` and `.app` simultaneously) so the script still works if Google flips back. See `scripts/install_google_earth.sh` in the env.

**Total cold install time:** ~50s (Rosetta install ~20s if not present + 82MB DMG download ~5s + .pkg install ~20s + misc).

---

## Rosetta Is Required

Google Earth Pro for Mac ships as an **x86_64-only** binary (Universal binary or arm64 build does not exist as of 2026). On Apple Silicon (use.computer is M4) it runs under Rosetta 2. Install pattern from `12_macos_environments.md` applies:

```bash
if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
  sudo softwareupdate --install-rosetta --agree-to-license
fi
```

If you skip this, the app launch silently fails and `pgrep` returns nothing.

---

## Launching: `open -a`, Not Spotlight

```bash
open -a "Google Earth Pro"
```

The use.computer `base-macos` image does **not respond to cmd+space**. Injecting that keyboard chord through `MacOSSandbox.keyboard.press("space", modifiers=["cmd"])` runs successfully (the API returns 200) but Spotlight never appears. Possibly Spotlight indexing is disabled in the base image, or the cmd+space binding is removed.

Use `open -a` via `exec_ssh` from `setup_task.sh`. This is the same as the rest of the cua_world google_earth tasks would do (they used `nohup google-earth-pro &` on Linux).

---

## First-Run Dialog ("Start-up Tips")

When Google Earth Pro launches for the first time in a fresh sandbox, the **"Start-up Tips"** modal blocks the globe view. Same as the Linux env.

- Window title: `Start-up Tips`
- Closes via the **Close** button (bottom-right of the dialog), not the Escape key
- Has a `Show tips at start-up` checkbox — unchecking before close prevents future appearances

For the smoke / launch-only task, the dialog being up is fine — process is running and window is registered. For navigation tasks where the agent needs to interact with the globe, dismiss the dialog in pre_task before handing off:

```bash
# After launch + window register, dismiss the Start-up Tips dialog if present.
# (osascript that walks AX over SSH may hit TCC; use the ax_helper / exec_ax
# path if you need it. For now: click the Close button by coordinates after
# screenshot inspection.)
```

(The current `launch_google_earth` smoke task doesn't dismiss the dialog — it's a deliberate "is the env up" check, not a navigation task.)

---

## State Files for Verifier Strategy

Per the Linux notes, prefer **file-based verifiers** over UI inspection:

| State | Path |
|-------|------|
| Saved placemarks | `~/Library/GoogleEarth/myplaces.kml` |
| Temporary places (session) | `~/Library/GoogleEarth/myplaces.backup.kml` |
| User preferences | `~/Library/Application Support/Google Earth Pro/` |
| Cache | `~/Library/Caches/Google Earth/` |

`setup_google_earth.sh` pre-creates `~/Library/Application Support/Google Earth Pro` and `~/Library/GoogleEarth` so app code doesn't trip on missing dirs.

For "did the agent add a placemark" tasks, parse `myplaces.kml` (XML) rather than relying on screenshot matching.

---

## Task Inventory (vs Linux equivalents)

The Linux google_earth env (per `specific_env_notes/google_earth/07_google_earth_todo.md`) had:
`navigate_to_location`, `search_coordinates`, `measure_distance`, `create_placemark`, `take_screenshot`.

Current macOS env (`benchmarks/cua_world-macos/environments/google_earth_env/tasks/`) has:
- `launch_google_earth` — smoke task; pre_task launches the app, agent no-ops, verifier checks `pgrep` + `lsappinfo`. Validates env install + launch end to end.

**Next tasks to add** (mirror Linux design):
- `navigate_to_paris` — pre_task launches; agent types in Search panel, hits Enter; verifier checks lat/lon in window title or zoom-out state via screenshot+VLM.
- `create_placemark` — pre_task launches; agent navigates + clicks "Add Placemark" + names it; verifier parses `myplaces.kml`.

---

## Known Gotchas

- **`set -eu` + brew `if`-guarded install**: brew install inside `if … ; then` doesn't trip set -e when it returns non-zero. The install script falls through to the DMG fallback as intended. Don't move the brew block outside the `if`.
- **`hdiutil attach` output parsing**: the tab-separated columns vary in count depending on whether a content hint and main hash are present. Use `awk -F'\t' '$NF ~ /^\/Volumes\//'` to pick the mount point reliably.
- **Quarantine bit**: `.pkg`-installed apps don't always carry `com.apple.quarantine`, but `sudo xattr -dr com.apple.quarantine "/Applications/Google Earth Pro.app"` is safe-no-op if absent.
