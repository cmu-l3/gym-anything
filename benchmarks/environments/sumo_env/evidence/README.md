# SUMO Environment - Evidence Documentation

## Environment Overview
- **Application**: SUMO (Simulation of Urban Mobility) v1.26.0 (Eclipse SUMO)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 6GB RAM, no GPU, network enabled
- **GUI Tools**: sumo-gui (simulation viewer), netedit (network editor)
- **Data Source**: Real-world Bologna, Italy traffic scenarios from DLR-TS/sumo-scenarios repository
- **Resolution**: 1920x1080

---

## Verification Checklist

### 1. Installation script completes without errors

**Status**: PASS

The `install_sumo.sh` pre_start hook installs SUMO v1.26.0 via PPA (`ppa:sumo/stable`), along with GUI automation tools (xdotool, wmctrl, scrot, imagemagick, pyautogui, xclip). It also downloads the Bologna Acosta and Pasubio scenarios from the DLR-TS/sumo-scenarios GitHub repository.

```
(from env_setup_pre_start.log)

=== Installing SUMO (Simulation of Urban Mobility) ===
Installing prerequisites...
Adding SUMO stable PPA...
Installing SUMO...
Installing automation tools...
=== SUMO installation complete ===
SUMO version: Eclipse SUMO sumo 1.26.0
sumo-gui available
netedit available
SUMO_HOME=/usr/share/sumo
```

Build features: KVM, Proj, GUI, Intl, SWIG, Eigen, GDAL, GL2PS

### 2. Setup script completes without errors

**Status**: PASS

The `setup_sumo.sh` post_start hook creates working directories, copies scenario files, creates desktop shortcuts and launch scripts, and sets SUMO_HOME environment variable.

```
(from env_setup_post_start.log)

=== Setting up SUMO environment ===
Creating working directories...
Copying Bologna Acosta scenario...
Copying Bologna Pasubio scenario...
=== SUMO setup complete ===
Scenarios available:
  - Bologna Acosta: /home/ga/SUMO_Scenarios/bologna_acosta/run.sumocfg
  - Bologna Pasubio: /home/ga/SUMO_Scenarios/bologna_pasubio/run.sumocfg
Output directory: /home/ga/SUMO_Output/
```

### 3. Application is visible in screenshot

**Status**: PASS

Both sumo-gui and netedit launch correctly and display in full-screen on the GNOME desktop. Verified via VNC screenshots during interactive testing.

Evidence screenshots:
- `sumo_gui_loaded.png` - sumo-gui with Bologna Acosta scenario loaded, road network visible
- `netedit_network_loaded.png` - netedit with Bologna Acosta network, 112 nodes and 117 edges
- `run_simulation_start.png` - Final test: sumo-gui ready for run_simulation task
- `change_traffic_light_phase_start.png` - Final test: netedit ready for traffic light task
- `add_vehicle_detector_start.png` - Final test: netedit ready for detector task
- `inspect_vehicle_route_start.png` - Final test: sumo-gui ready for vehicle inspection
- `export_network_statistics_start.png` - Final test: sumo-gui with Bologna Pasubio loaded

### 4. Application is in correct initial state with real data loaded

**Status**: PASS

Each task's `setup_task.sh` launches the correct SUMO application (sumo-gui or netedit) with the appropriate scenario and flags. Verified interactively via VNC + visual_grounding MCP tool.

- **sumo-gui tasks**: Simulation loaded in paused state (no `--start`), agent must press Ctrl+A to begin
- **netedit tasks**: Network file loaded with `-s` flag, additionals loaded with `-a` flag where needed
- **Data**: Bologna Acosta (112 nodes, 117+ edges, ~2MB) and Pasubio (similar, different area)

### 5. Task setup runs without errors (all 5 tasks)

**Status**: PASS

All 5 tasks were tested via `from_config()` API with `use_cache=True, cache_level="pre_start", use_savevm=True`. Each task booted successfully and presented the correct start state.

### 6. Tasks are completable interactively (all 5 tasks)

**Status**: PASS

Each task was tested interactively via SSH + VNC, performing the exact steps an agent would need to complete the task.

#### Task 1: run_simulation (Medium)
- Change vehicle coloring to "by speed" via F9 > Vehicles tab > Color dropdown
- Start simulation with Ctrl+A, take screenshot with scrot
- **Verified**: Color dropdown changed, vehicles appear color-coded after simulation starts

#### Task 2: change_traffic_light_phase (Medium)
- Switch to Traffic Light mode ('T'), click junction, edit phase duration to 45s
- Save with Ctrl+Shift+K to TLS programs file
- **Verified**: Phase table shows edited duration, file saves correctly

#### Task 3: add_vehicle_detector (Medium)
- Switch to Additional mode ('A'), select "E1 inductionLoop" from dropdown
- Set id="new_detector_1", period=300, file="new_detector_output.xml"
- Click lane to place, save with Ctrl+Shift+A
- **Verified**: XML output contains `<inductionLoop id="new_detector_1" lane="..." pos="..." period="300.00" file="new_detector_output.xml"/>`

#### Task 4: inspect_vehicle_route (Medium)
- Start sim with Ctrl+A, use Vehicle Chooser (Shift+V) to locate vehicles (672 objects in Bologna Acosta)
- Right-click vehicle shows context menu with "Show Current Route" and "Show Parameters"
- **Verified**: Route highlighted in green on map, parameter dialog shows speed/position/route

#### Task 5: export_network_statistics (Medium)
- Open View Settings (F9), click Streets tab, change coloring to "by current occupancy (lanewise, brutto)"
- Click OK, start sim with Ctrl+A, take screenshot with scrot
- **Verified**: Roads color-coded by occupancy (white=empty, green/warm=occupied)

---

## Final Test Results

All 5 tasks passed the clean final test:

```json
{
  "run_simulation": {"status": "PASS", "ssh_port": 2370},
  "change_traffic_light_phase": {"status": "PASS", "ssh_port": 2240},
  "add_vehicle_detector": {"status": "PASS", "ssh_port": 2370},
  "inspect_vehicle_route": {"status": "PASS", "ssh_port": 2278},
  "export_network_statistics": {"status": "PASS", "ssh_port": 2250}
}
```

---

## Evidence Files

### Screenshots
| File | Description |
|------|-------------|
| `sumo_gui_loaded.png` | sumo-gui with Bologna Acosta scenario loaded |
| `sumo_simulation_complete.png` | Simulation ran to completion (time 5655.00) |
| `netedit_network_loaded.png` | netedit with 112 nodes and 117 edges |
| `netedit_traffic_light_task.png` | netedit ready for traffic light editing |
| `run_simulation_start.png` | Task 1 start state: sumo-gui with Acosta scenario |
| `change_traffic_light_phase_start.png` | Task 2 start state: netedit with network |
| `add_vehicle_detector_start.png` | Task 3 start state: netedit with network + additionals |
| `inspect_vehicle_route_start.png` | Task 4 start state: sumo-gui with Acosta scenario |
| `export_network_statistics_start.png` | Task 5 start state: sumo-gui with Pasubio scenario |

### Data Files
| File | Description |
|------|-------------|
| `test_results.json` | Final test results for all 5 tasks |

---

## Data Sources

### Bologna Acosta Scenario
- **Source**: https://github.com/DLR-TS/sumo-scenarios/tree/main/bologna/acosta
- **Origin**: Real-world traffic data from the Acosta area in Bologna, Italy (iTETRIS project)
- **Files**: Network (256KB), Routes (1.7MB), Bus routes (60KB), Detectors, Traffic lights, Vehicle types, Bus stops
- **Network**: 112 nodes, 117+ edges (real street network)

### Bologna Pasubio Scenario
- **Source**: https://github.com/DLR-TS/sumo-scenarios/tree/main/bologna/pasubio
- **Origin**: Real-world traffic data from the Pasubio area in Bologna, Italy
- **Files**: Network (196KB), Routes (1.6MB), Bus routes (50KB), Detectors, Traffic lights, Vehicle types, Bus stops

---

## Known Quirks and Fixes

1. **`--start` flag causes issues**: Using `sumo-gui --start` runs the simulation at max speed before the agent can interact. All tasks now launch without `--start`; agents press Ctrl+A to begin.

2. **Ctrl+A vs play button**: The play button in the toolbar is hard for agents to target precisely. Ctrl+A is the most reliable method to start/pause simulation.

3. **netedit text fields truncate**: The FOX toolkit renders narrow text fields that truncate long values like "new_detector_1". Use xclip clipboard verification rather than visual inspection to confirm field contents.

4. **Vehicle right-click precision**: Vehicles in sumo-gui are very small at default zoom. Use Vehicle Chooser (Shift+V) to locate and center on a vehicle before right-clicking, or zoom in significantly.

5. **netedit `-s` flag for network**: netedit requires `-s network.xml` (not positional args) to load a network file. Use `-a additional.xml` for additional files.

6. **View Settings dropdown**: The coloring dropdown in F9 > Streets/Vehicles uses a tree-style selection. The exact option name for occupancy is "by current occupancy (lanewise, brutto)" — partial matches won't work.

7. **scrot for screenshots**: SUMO has no built-in screenshot export. Use `scrot /path/to/file.png` from a terminal for screenshot capture.

---

## Timing

- SUMO PPA install: ~60-70s
- Scenario file copy: ~1s
- sumo-gui launch + load: ~5-8s
- netedit launch + load: ~5-8s
- Task pre_task setup: ~10s
- Total environment setup (clean, no cache): ~80s
