# Task: advanced_privacy_hardening

## Domain Context

Privacy engineers and digital rights practitioners regularly configure hardened browser profiles for clients under threat — journalists, activists, lawyers, and whistleblowers who operate in hostile surveillance environments. Preparing a hardened Tor Browser profile is a standard operational security (OPSEC) task that requires knowing which specific preferences control privacy-sensitive behaviors and navigating both the Settings UI and the advanced `about:config` interface.

## Goal

Apply a complete set of 6 privacy hardening measures to a running Tor Browser instance, following a specific threat model protocol for a high-risk journalist client. The final state must have ALL of the following applied:

1. Security Level = **Safest** (slider value = 4)
2. HTTPS-Only Mode = **enabled** for all windows
3. `network.prefetch-next` = **false** (disables DNS prefetching)
4. `browser.sessionstore.privacy_level` = **2** (no session data saved to disk)
5. `network.http.speculative-parallel-limit` = **0** (no speculative connections)
6. History saving = **disabled** (Never remember history or auto-start private browsing)

## Difficulty

**very_hard** — Requires knowledge of both the Settings UI and `about:config`, must locate 3 non-obvious preference names and change their types/values correctly, and must apply all 6 changes correctly.

## Success Criteria

- **Pass threshold**: 60+ points AND Security Level = Safest (required gate)
- Full score: 100 points across 6 criteria
- Partial: Any subset of criteria awards proportional points

## Scoring Breakdown

| Criterion | Points | Required |
|-----------|--------|----------|
| Security level = Safest (slider=4) | 20 | Yes (gate) |
| HTTPS-Only Mode enabled | 20 | No |
| network.prefetch-next = false | 15 | No |
| browser.sessionstore.privacy_level = 2 | 15 | No |
| network.http.speculative-parallel-limit = 0 | 15 | No |
| History never saved | 15 | No |

## Verification Strategy

**Primary**: Read `prefs.js` from the Tor Browser profile after the agent finishes. Each preference is stored in this file when changed through the browser UI or `about:config`.

**Profile path**: `~/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/prefs.js`

**Security slider values**: 1=Standard, 2=Safer, 4=Safest

**Key preference patterns**:
- `browser.security_level.security_slider` (integer: 4 = Safest)
- `dom.security.https_only_mode` (boolean: true)
- `network.prefetch-next` (boolean: false)
- `browser.sessionstore.privacy_level` (integer: 2)
- `network.http.speculative-parallel-limit` (integer: 0)
- `places.history.enabled` (boolean: false) OR `browser.privatebrowsing.autostart` (boolean: true)

## Starting State

Tor Browser is launched and connected to the Tor network, showing the DuckDuckGo onion homepage. Security level is at default "Standard". All target preferences are at their default (non-hardened) values.

## Edge Cases

- `about:config` requires the agent to navigate to it in the URL bar and then search for each preference by name
- Some preferences may not exist in `prefs.js` until explicitly changed (they're only written when non-default)
- The HTTPS-Only Mode setting is in Settings → Privacy & Security → HTTPS-Only Mode section
- History setting is in Settings → Privacy & Security → History section (choose "Never remember history" or use custom settings)
- `browser.sessionstore.privacy_level`: valid values are 0 (normal), 1 (encrypted only), 2 (never save)
- The security level change requires a browser restart to take full effect, but the preference is saved immediately
