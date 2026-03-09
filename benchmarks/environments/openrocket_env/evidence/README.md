# OpenRocket Environment - Evidence Documentation

## Environment Verification Checklist

### 1. Installation Script Completes Without Errors
**Status: PASS**

The `install_openrocket.sh` pre_start hook completes successfully:
- Java 17 (OpenJDK 17.0.18) installed
- OpenRocket 24.12 JAR (80MB) downloaded from GitHub releases
- 13 real .ork rocket design files downloaded from official sources
- GUI automation tools (xdotool, wmctrl, scrot) installed

**Log excerpt (pre_start tail):**
```
Downloading OpenRocket 24.12...
OpenRocket JAR downloaded: -rw-r--r-- 1 root root 80M Jul 27  2025 /opt/openrocket/OpenRocket.jar
=== Downloading real rocket design files ===
Downloaded 13 .ork rocket design files
=== Verification ===
openjdk version "17.0.18" 2026-01-20
OpenJDK Runtime Environment (build 17.0.18+8-Ubuntu-122.04.1)
OpenRocket JAR: -rw-r--r-- 1 root root 80M Jul 27  2025 /opt/openrocket/OpenRocket.jar
Rocket files: 13 designs
=== OpenRocket installation complete ===
```

### 2. Setup Script Completes Without Errors
**Status: PASS**

The `setup_openrocket.sh` post_start hook:
- Creates working directories (~/Documents/rockets, ~/Documents/exports, ~/Desktop)
- Creates desktop launcher and .desktop file
- Lists all 13 available .ork rocket design files

**Log excerpt (post_start tail):**
```
=== Available rocket designs ===
-rw-r--r-- 1 ga ga  198735 ... simple_model_rocket.ork
-rw-r--r-- 1 ga ga  117850 ... two_stage_high_power_rocket.ork
-rw-r--r-- 1 ga ga  797075 ... EPFL_BellaLui_2020.ork
... (13 files total)
=== OpenRocket setup complete ===
```

### 3. Application Visible in Screenshot
**Status: PASS**

See: `01_openrocket_running_with_rocket_design.png`

OpenRocket launches correctly with:
- Component tree showing full rocket hierarchy
- Side view rocket visualization with CG/CP markers
- "Add new component" palette with all component types
- Flight simulation data (Apogee: 317m, Max velocity: 95.3 m/s)

### 4. Application in Correct Initial State with Real Data
**Status: PASS**

See: `02_task_start_state_add_fins.png`

For the `add_fins_to_rocket` task:
- OpenRocket opens with `simple_model_rocket.ork` loaded
- The rocket design is a real official OpenRocket example (from github.com/openrocket/openrocket)
- Component tree visible with nose cone, body tube, parachute, fins, motor mount
- "Add new component" panel visible with Trapezoidal fin button accessible

### 5. Task Setup Runs Without Errors
**Status: PASS**

**Task pre_task log:**
```
=== Setting up add_fins_to_rocket task ===
OpenRocket window detected after 2s
=== Task setup complete ===
```

### 6. Task Start State Verified via Visual Grounding
**Status: PASS**

Visual grounding analysis confirms:
- OpenRocket application window open and maximized
- "A simple model rocket" design loaded
- Component tree on left shows full hierarchy
- "Add new component" panel on right shows Trapezoidal fins button
- Agent can see where to click to add fins (Trapezoidal button coordinates identified)
- Rocket visualization with measurements visible

### 7. Sufficient Evidence of Task Completability
**Status: PASS**

The visual grounding identified specific UI coordinates for task completion:
- "Body tube" in tree at normalized (131, 136) → actual (197, 204)
- "Trapezoidal" fins button at normalized (1011, 215) → actual (1517, 323)
- File > Save As accessible from menu bar
- Component property editor opens on double-click

## Real Data Sources

All .ork rocket design files are REAL designs from verified sources:

| File | Source | Description |
|------|--------|-------------|
| simple_model_rocket.ork | Official OpenRocket examples | Basic model rocket |
| two_stage_high_power_rocket.ork | Official OpenRocket examples | Two-stage HP rocket |
| three_stage_low_power_rocket.ork | Official OpenRocket examples | Three-stage LP rocket |
| dual_parachute_deployment.ork | Official OpenRocket examples | Dual deployment design |
| clustered_motors.ork | Official OpenRocket examples | Clustered motor design |
| tube_fin_rocket.ork | Official OpenRocket examples | Tube fin design |
| parallel_booster_staging.ork | Official OpenRocket examples | Parallel booster |
| chute_release.ork | Official OpenRocket examples | Chute release mechanism |
| EPFL_BellaLui_2020.ork | RocketPy-Team/RocketSerializer | Real EPFL university rocket |
| NDRT_Rocket_2020.ork | RocketPy-Team/RocketSerializer | Real Notre Dame team rocket |
| ProjetoJupiter_Valetudo_2019.ork | RocketPy-Team/RocketSerializer | Real Brazilian team rocket |
| janus_29mm.ork | 3dp-rocket/rockets | Real 3D-printable rocket |
| janus_38mm.ork | 3dp-rocket/rockets | Real 3D-printable rocket |

## Timing

| Phase | Duration |
|-------|----------|
| Full env setup (first run) | ~174s |
| Task-specific hooks | ~14.7s |
| Total (first run) | ~251s |
| Total (cached) | ~85s |
