# Task: Safari DevTools — Security Header Audit

**Difficulty:** hard
**Source port:** `benchmarks/cua_world/environments/firefox_env/tasks/devtools_security_header_audit`
**Occupation:** Software / Web Developer (importance ~90 in master_dataset)

## Domain Context

Web developers routinely benchmark competitor platforms' HTTP security posture before shipping their own service. Strict-Transport-Security (HSTS), Content-Security-Policy (CSP), X-Content-Type-Options, and X-Frame-Options collectively form the first line of defense against transport downgrade, XSS, MIME-sniffing, and clickjacking. Auditing a peer-group of sites (e.g., the five major source-code / package hosts in this task) gives a developer a concrete baseline to argue from.

## Goal

Use Safari's Web Inspector to read the actual response-header values served by **github.com, gitlab.com, bitbucket.org, npmjs.com, pypi.org** and produce a JSON audit report at `~/Documents/security_audit_report.json`.

For each site, the report must contain real, non-empty string values for at least **3 of these 4 headers**:

- `Strict-Transport-Security`
- `Content-Security-Policy` (or `Content-Security-Policy-Report-Only`)
- `X-Content-Type-Options`
- `X-Frame-Options` (or a `frame-ancestors` CSP directive)

## Expected JSON Shape

```json
{
  "github.com":     {"strict-transport-security": "max-age=...", "content-security-policy": "default-src ...", "x-content-type-options": "nosniff", "x-frame-options": "deny"},
  "gitlab.com":     { ... },
  "bitbucket.org":  { ... },
  "npmjs.com":      { ... },
  "pypi.org":       { ... }
}
```

Keys may be case-insensitive variants ("Strict-Transport-Security" or "hsts" both match). Site keys are matched on the bare domain, case-insensitive.

## Why This Is Hard

- Five distinct sites, each requiring a fresh navigation + reload + header inspection.
- Web Inspector workflow is non-obvious in Safari: requires Develop menu enabled, then a specific sequence (open Inspector → Network tab → reload → select main document → Headers panel).
- The four headers live in different parts of the response: HSTS and X-Content-Type-Options are simple strings, CSP is a multi-directive structured value, X-Frame-Options is sometimes superseded by CSP `frame-ancestors`.
- The agent must record header values, not just observe them — writing a structured JSON file with the correct shape.

## Verification Strategy (5 criteria, 100 pts, pass at 60)

| # | Criterion | Pts |
|---|---|---|
| 1 | Each required site visited after task start (via Safari History.db) | 25 (5 × 5 sites, binary) |
| 2 | Report file exists, fresh (`mtime > task_start`), and valid JSON | 15 (partial 8 / 3) |
| 3 | All 5 required sites present as keys in the JSON | 20 (4 × 5 sites, binary) |
| 4 | Each site has ≥3 non-empty header fields | 25 (5 × 5 sites, partial 2 if 1-2) |
| 5 | Header values look plausible: HSTS has `max-age`, CSP has a source directive | 15 (HSTS 8 / CSP 7, 2-step partials) |

**Partial-credit safety check (Anti-Pattern 4):** worst-case partial-only score is `0 + 8 + 0 + (2×5) + (4+3) = 25`, well under the 60 pass threshold.

## Setup / Export Pipeline

- **setup_task.sh** quits any running Safari, asserts `IncludeDevelopMenu`, flushes `cfprefsd`, deletes any pre-existing report (anti-gaming), records `/tmp/task_start_timestamp` (Unix epoch), launches Safari, and navigates to `about:blank`.
- **export_result.sh** quits Safari (to flush History.db WAL), queries `~/Library/Safari/History.db` for per-domain visit counts after task start (with Mac-absolute-time conversion), checks the report file's existence + freshness + JSON validity, and emits a structured result to `/tmp/devtools_security_header_audit_result.json` that `verifier.py` consumes.

## Anti-Gaming Notes

- Pre-existing report is deleted in setup, and the verifier requires `mtime > task_start` for full credit on Criterion 2.
- Header values must be non-empty strings of length > 3 to count toward Criterion 4 — `"true"`, `"x"`, or empty strings don't pass.
- HSTS values lacking `max-age` and CSP values lacking any source directive don't earn Criterion 5 points, preventing trivially-fake values from scoring.
- **Per-site visit gating (hardening over the source firefox port)**: Criteria 3, 4, and 5 contributions for each site are gated on Safari's `History.db` showing a visit to that site after task start. An agent that fabricates a plausible JSON without ever opening a Web Inspector therefore scores only C2 (15 pts) — well below the 60 threshold. Without this gate, fabricated-perfect-JSON would have scored 75 (the gap is documented in the source verifier and addressed here). See Anti-Pattern 13 in `14_task_design_antipatterns.md`.
- **Strategy enumeration table** (verified by `/tmp/test_safari_security_header_verifier.py` offline mocks):

| Strategy | C1 | C2 | C3 | C4 | C5 | Total | Pass? |
|---|---|---|---|---|---|---|---|
| Do-nothing | 0 | 0 | 0 | 0 | 0 | 0 | No |
| Wrong-target (browse unrelated sites + report on them) | 0 | 15 | 0 | 0 | 0 | 15 | No |
| Fabricated JSON, no browsing | 0 | 15 | 0 (gated) | 0 (gated) | 0 (gated) | 15 | No |
| Partial: 2/5 sites done end-to-end | 10 | 15 | 8 | 10 | 7 | 50 | No |
| Stale report (predates task start) | 0 | 8 | 0 | 0 | 0 | 8 | No |
| Invalid JSON file | 0 | 3 | 0 | 0 | 0 | 3 | No |
| Correct: all 5 sites browsed + reported | 25 | 15 | 20 | 25 | 15 | 100 | Yes |

## Live Behavior Notes (macOS / use.computer)

- Safari's `IncludeDevelopMenu` requires `killall cfprefsd` after `defaults write` for the Develop menu to appear in the menu bar on first launch — both `setup_safari.sh` (env post_start) and this task's `setup_task.sh` do it.
- Safari's `History.db` uses WAL mode. `export_result.sh` quits Safari before reading to ensure the WAL has been flushed.
- Mac absolute time = Unix epoch − 978307200. The export script converts before comparing.
