# Vicidial Environment Evidence (Real Run)

Run date: 2026-02-14

## Latest Clean Run (No Cache)

The folder `run3_2026-02-14/` contains evidence from a clean `env.reset(seed=42, use_cache=False)` run.

Key confirmations:
- Task start screenshot shows the Vicidial **"ADD A NEW LIST"** page (no HTTP Basic Auth dialog blocking the UI).
- The real CSV exists in the VM and has 100 lead rows.
- Vicidial DB state is deterministic at task start (list `9001` does not exist; 0 leads for list `9001`).
- The default Vicidial admin user `6666` has list/lead permissions enabled.
- `run5_2026-02-14/` confirms the same start state while also showing Firefox starts with a single tab (no extra homepage tab).

## Display Resolution Verification

- `run3_2026-02-14/xdpyinfo_dimensions.txt` shows `1920x1080` (used for VLM coordinate scaling).

## Environment Startup Evidence

Logs:
- `run3_2026-02-14/env_setup_pre_start.log`: apt installs for Docker, Firefox, and GUI automation tools.
- `run3_2026-02-14/env_setup_post_start.log`: creation of the Vicidial Docker service, Firefox profile, and initial launch.
- `run3_2026-02-14/vicidial-startup.log`: output from the `vicidial-ensure-running` readiness script.

Screenshots:
- `run3_2026-02-14/task_start.png`: Firefox showing Vicidial Admin "ADD A NEW LIST" page at task start.

Key readiness snippet:
```text
2026-02-14 20:28:17 - Vicidial container is running after 1s
2026-02-14 20:28:18 - Vicidial web UI reachable at http://localhost/vicidial/admin.php after 2s (HTTP 200)
```

## Task Start-State Evidence

The task `import_us_senators_leads` starts with Firefox focused and navigated to the Vicidial **"ADD A NEW LIST"** page (`admin.php?ADD=111`).

- `run3_2026-02-14/task_start.png`: deterministic task start state (Add New List form visible; no blocking auth dialog).
- `run3_2026-02-14/visual_grounding_task_start.txt`: visual grounding confirmation of the start state.

## Real-World Data Included

Lead CSV placed in the VM at:
- `/home/ga/Documents/VicidialData/us_senators_vicidial_standard_format_list9001_2026-02-14.csv`

Source data is U.S. Senate public contact information (see `benchmarks/environments/vicidial_env/assets/README.md`).
