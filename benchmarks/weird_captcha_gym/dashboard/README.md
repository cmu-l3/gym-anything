# CAPTCHA Bench Dashboard

The dashboard is the visual control plane for Weird CAPTCHA Gym. It presents 65 real environment folders—63 evidence-backed built designs and 2 rejected archive pilots—with screenshots, solution reels, task contracts, human reviews, local launches, VNC sessions, and evaluation controls tied to the same environment identities.

The dashboard is local-first. A shared static copy can be hosted for collaborators, but puzzle execution never moves to that host: each collaborator runs a small authenticated companion on `127.0.0.1`, and every puzzle, VNC guest, review write, and evaluation process stays on their own computer.

The mined Survey corpus is deliberately excluded from this product and from static exports.

## Run the complete dashboard locally

From the repository root:

```bash
PYTHONPATH=src python benchmarks/weird_captcha_gym/dashboard/server.py --open --runner avf
```

Then visit <http://127.0.0.1:8767>. The server binds to localhost by default.

`avf` is the normal runner on Apple Silicon. `qemu`, `qemu_native`, `docker`, and `local` remain available when the corresponding Gym-Anything runner is configured.

## Build the shared static dashboard

```bash
PYTHONPATH=src python benchmarks/weird_captcha_gym/dashboard/export_static.py \
  --output dist/captcha-bench-dashboard
```

The export contains:

- the full 65-environment catalog;
- every catalog screenshot and all 11 solution reels;
- Observatory, Environments, Review queue, Live sessions, and Evaluations;
- a shared-mode configuration pointing at `http://127.0.0.1:8767`;
- no Survey APIs, records, artifacts, or navigation.

The resulting directory is ordinary static HTML/CSS/JavaScript and can be served by any HTTPS-capable static host. For a local deployment rehearsal:

```bash
python -m http.server 8080 --directory dist/captcha-bench-dashboard
```

The repository's existing GitHub Pages workflow publishes this export alongside the main project site at:

<https://cmu-l3.github.io/gym-anything/captcha-bench/>

It deploys automatically after changes reach `main`. The dashboard stays under Pages' `/captcha-bench/` subpath; all frontend and media URLs are relative so the same artifact remains portable to another static host.

## Connect a collaborator's computer

From their repository checkout, the collaborator runs:

```bash
PYTHONPATH=src python benchmarks/weird_captcha_gym/dashboard/server.py \
  --companion \
  --allow-origin https://your-dashboard.example
```

For the local rehearsal above, use `--allow-origin http://127.0.0.1:8080`.

For the GitHub Pages deployment, use `--allow-origin https://cmu-l3.github.io` (the browser `Origin` excludes `/gym-anything/captcha-bench/`).

The companion prints a persistent pairing key. Open **LOCAL COMPANION** in the dashboard sidebar and paste that key once. It is stored only in that browser's local storage and sent only to the loopback companion.

Chrome 142 and newer asks whether the shared dashboard may find and connect to devices on the local network. Choose **Allow**: this is the browser's Local Network Access gate for the explicit `127.0.0.1` companion. The shared deployment itself should use HTTPS; the loopback companion intentionally remains HTTP and never leaves the collaborator's machine.

Companion mode has three safety boundaries:

- it refuses to bind to a non-loopback address;
- it accepts cross-origin requests only from exact origins passed with `--allow-origin`;
- every API except the non-sensitive health probe requires the pairing key.

The server keeps legacy Private Network Access preflight compatibility in addition to current Local Network Access behavior. No VNC password, filesystem path, review, or process control is published by the static host; those details arrive from the paired local machine and remain visible to the collaborator as requested.

## Launch modes

Every built environment supports two launch paths from the same dashboard:

- **Local browser** — the default one-click path. The companion runs the real seeded task setup, starts the shared puzzle UI and grader on an ephemeral localhost port, and opens a normal browser tab. No VM is involved.
- **Isolated VNC guest** — the existing Gym-Anything path. The companion starts the selected runner, waits for `SessionInfo`, exposes the real VNC address/password, and can open TigerVNC.

The Live sessions page manages both kinds together. It keeps the existing two-active-session limit, prevents duplicate launches of one environment, exposes logs and local paths, supports reconnect/open, and terminates the owned process group on stop or companion shutdown.

## Product surfaces

- **Observatory** — screenshot-first overview of the interaction-first benchmark principles and all six packs.
- **Environments** — searchable and filterable collection of 63 built candidates plus 2 rejected pilots retained as an honest archive.
- **Review queue** — pending, looks-good, approved, and revision-requested lanes with notes and decision history.
- **Environment dossier** — evidence filmstrip, solution reel when available, task instruction, verifier state, launch controls, and review desk.
- **Live sessions** — local-browser and VNC process lifecycle, addresses, passwords, logs, reconnect, and teardown.
- **Evaluations** — safe command previews by default, with explicit opt-in to execute the existing `gym_anything.cli benchmark` path locally.

Review decisions default to the historical research ledger when it exists, preserving the current project's decisions. In a clean collaborator checkout they live at `~/.captcha-bench/environment-reviews.json`. Set `CAPTCHA_BENCH_REVIEW_PATH` or pass `--review-path` to relocate the ledger.

## Verification

Run the backend, export, security, catalog, and browser-launch tests:

```bash
PYTHONPATH=src python -m pytest tests/test_weird_captcha_dashboard.py -q
```

Run the dashboard browser smoke:

```bash
python benchmarks/weird_captcha_gym/tools/smoke_dashboard_ui.py \
  --base-url http://127.0.0.1:8767 \
  --exercise-reviews
```

Exercise the complete shared-site boundary—including static export, browser pairing, localhost companion, a real Domino browser task, and teardown:

```bash
python benchmarks/weird_captcha_gym/tools/smoke_dashboard_shared.py
```

With a configured runner, the opt-in VNC smoke still exercises the real guest protocol and teardown path:

```bash
python benchmarks/weird_captcha_gym/tools/smoke_dashboard_live_vnc.py \
  --base-url http://127.0.0.1:8767
```

## Architecture

```text
63 built folders + task.json + evidence media ──► catalog.py ──► static export
            │                                          │
            │                                          └─► shared dashboard host
            │                                                       │
            ├─► setup_task.py ─► local puzzle server ◄──────────────┤
            │            normal browser tab                         │
            │                                                       ▼
            ├─► session_worker.py ─► Gym-Anything / VNC     paired localhost companion
            │
            └─► benchmark CLI ─► local evaluation process

local environment-reviews.json ─► reviews.py ─► review queue + dossier desk
```

The backend uses the Python standard library. The frontend remains dependency-free HTML, CSS, and JavaScript, so both the local dashboard and its static export boot without a package install or frontend build step.

See [`RESEARCH.md`](RESEARCH.md) for the visual product research behind the interface and [`docs/interaction-puzzle-field-notes.md`](../docs/interaction-puzzle-field-notes.md) for the binding interaction-quality doctrine.
