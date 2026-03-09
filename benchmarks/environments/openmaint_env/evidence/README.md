# OpenMaint Environment Evidence

## Environment Summary

- Application: OpenMaint 2.4 (CMDBuild 4.1.0 stack)
- Environment ID: `openmaint_env@0.1`
- Task ID: `login_to_openmaint_and_open_buildings@1`
- Base: `ubuntu-gnome-systemd_highres`
- Test date: 2026-02-14

## Real Data Source

This environment uses the OpenMaint vendor/maintainer demo dump by setting:

- `CMDBUILD_DUMP=demo.dump.xz`

in `benchmarks/environments/openmaint_env/config/docker-compose.yml`.

This is sourced from the maintained OpenMaint Docker deployment artifacts (`itmicus/cmdbuild_docker`, `openmaint-2.4-4.1.0`).

## Checklist Results

- [x] `pre_start` installs Docker, Firefox, and GUI automation tools
- [x] `post_start` starts `openmaint_db` and `openmaint_app`
- [x] OpenMaint web UI is reachable at `http://localhost:8090/cmdbuild/ui/`
- [x] Task `pre_task` runs and places Firefox at OpenMaint login/start page
- [x] Demo dataset is loaded (database is non-empty and production-like)
- [x] Screenshots captured from live VM state
- [x] Task is completable interactively (logged in and opened Buildings cards with demo rows visible)

## Runtime Evidence

### Docker status (`docker_ps.txt`)

```
NAMES           STATUS                        PORTS
openmaint_app   Up About a minute (healthy)   0.0.0.0:8090->8080/tcp, [::]:8090->8080/tcp
openmaint_db    Up About a minute (healthy)   0.0.0.0:5432->5432/tcp, [::]:5432->5432/tcp
```

### HTTP check (`openmaint_http_status.txt`)

```
HTTP/1.1 200
```

### DB footprint (`openmaint_db_count.txt`)

```
729
```

(Count is from `SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';`)

### Buildings rows (`openmaint_building_count.txt`)

```
5
```

(Count is from `SELECT COUNT(*) FROM "Building";`.)

### Window state (`wmctrl_windows.txt`)

```
0x02000003 -1 ga-base @!0,0;BDHF
0x00800003  0 ga-base openMAINT - DEMO — Mozilla Firefox
```

## Hook Log Snippets

### `env_setup_post_start.log`

```
Container openmaint_db healthy after 0s
Container openmaint_app healthy after 35s
OpenMaint reachable at http://localhost:8090/cmdbuild/ui/ after 10s (HTTP 200)
=== OpenMaint setup complete ===
```

### `task_pre_task.log`

```
=== Setting up login_to_openmaint_and_open_buildings task ===
=== Task setup complete ===
Credentials: admin / admin
Goal: login and open Buildings list with demo building records visible
```

## Residual Risk

- The setup depends on Docker Hub images (`postgis/postgis` and `itmicus/cmdbuild`). In high-traffic/shared IP environments, unauthenticated pull-rate limits can affect repeated fresh resets.
- Optional mitigation exists but no credentials are stored in-repo: provide `/workspace/config/dockerhub_login.env` at runtime (see `config/dockerhub_login.env.example`) to authenticate pulls.

## Screenshots

- `01_openmaint_post_reset.png`: desktop state after full `env.reset`
- `02_task_start.png`: deterministic task-start capture with OpenMaint login visible
- `03_firefox_focused.png`: stabilized/focused Firefox capture with OpenMaint login visible
- `interactive_08_current.png`: logged-in OpenMaint state (`Corrective maintenance`)
- `interactive_11_buildings_url_try1.png`: interactive navigation result at `/#classes/Building/cards`
- `interactive_12_buildings_final.png`: final clean evidence with Buildings cards and 5 demo records visible

## Interactive Completion Notes

Live interactive testing (no mock scripts) was performed in a running VM session on 2026-02-14:

1. Reset environment with `use_cache=False`.
2. Logged into OpenMaint in Firefox (`admin` / `admin`).
3. Navigated to Buildings cards view (`/#classes/Building/cards`) and confirmed demo records are visible.
4. Captured screenshots and refreshed logs from the same run.

Coordinate-scaling reference:

- `screen_dimensions.txt` confirms VM display resolution is `1920x1080`.
- This matches scaling guidance (from 1280x720 normalized coordinates to native 1920x1080).
