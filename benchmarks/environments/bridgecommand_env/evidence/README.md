# Bridge Command Environment - Evidence Documentation

## Environment Overview

Bridge Command is a free, open-source 3D ship bridge simulator (GPL-2.0) used for maritime navigation training, radar operation, and ship handling practice. The environment provides two tasks for agent interaction.

- **Application**: Bridge Command v5.10.4-alpha.4 (built from source)
- **Type**: Desktop 3D simulation (Irrlicht engine, OpenGL)
- **Base Image**: ubuntu-gnome-systemd_highres (Ubuntu 22.04)
- **Resources**: 4 CPU, 8GB RAM, no GPU required (software rendering)

## Installation Method

Built from source (GitHub: `bridgecommand/bc`) because the .deb package requires Ubuntu 24.04+ (libc6 >= 2.38). The VM runs Ubuntu 22.04 (libc6 2.35).

### Build Dependencies
- cmake, build-essential, mesa-common-dev, libxxf86vm-dev
- freeglut3-dev, libxext-dev, libxcursor-dev
- portaudio19-dev, libsndfile1-dev, libopenxr-dev

### Install Location
- Binary: `/opt/bridgecommand/bridgecommand`
- Data (Scenarios, Models, World): `/opt/bridgecommand/`
- Config: `/home/ga/.config/Bridge Command/bc5.ini`

## Real Data

Bridge Command ships with real-world maritime training scenarios:
- **Simple Estuary** training area with IALA buoyage
- **Portsmouth Harbour** (UK) - day and night approaches (lat 50.78°N, lon 1.10°W)
- **Swinomish Channel** (WA, USA) - day and night
- **River navigation** and harbour departure scenarios
- Real vessel types: Tanker, Yacht, ASD Tug, Steam vessel
- Real navigation marks, lights, and buoyage systems

Additionally, a custom scenario (`m) Portsmouth Approach Custom`) was created using real Portsmouth Harbour coordinates with traffic vessels.

## Tasks

### Task 1: select_and_start_scenario (easy)
- **Description**: Select 'i) Portsmouth Night Entry' scenario from the launcher, start the simulation
- **Start State**: Bridge Command launcher visible with all menu buttons
- **Steps**: Click "Start Bridge Command" → Select scenario → Click OK → Wait for load → Click to start
- **Real Data**: Portsmouth Harbour night entry with real coordinates, real navigation lights

### Task 2: configure_simulation_settings (medium)
- **Description**: Open settings, change view_angle from 90 to 60 degrees, save settings
- **Start State**: Bridge Command launcher visible with Settings: Main button accessible
- **Steps**: Click "Settings: Main" → Find view_angle → Change to 60 → Click "Save and exit"
- **Real Data**: Settings reflect real maritime simulation parameters

## Evidence Screenshots

| File | Description |
|------|-------------|
| `01_launcher_screen.png` | Bridge Command launcher with all menu buttons visible |
| `02_scenario_selection.png` | Scenario dropdown showing all available scenarios |
| `03_simulation_running.png` | Running nighttime simulation with radar, navigation lights, ship controls |
| `04_settings_editor.png` | Settings editor showing view_angle=90 and other configuration options |
| `05_final_task_start_state.png` | Clean final test - launcher ready for agent interaction |
| `06_simulation_paused.png` | Loaded scenario in paused state showing ship position and instruments |

## Setup Logs

### Pre-start (install) - Key outputs
```
=== Installing Bridge Command ===
Building Bridge Command from source...
Running cmake...
Compiling...
Build successful
Installing to /opt/bridgecommand...
Scenarios: a) Buoyage, b) Buoyage by night, ..., l) Swinomish Channel day
=== Bridge Command installation complete ===
```

### Post-start (setup) - Key outputs
```
=== Setting up Bridge Command ===
Bridge Command binary: /opt/bridgecommand/bridgecommand
Copied pre-configured bc5.ini to user config
Installing custom scenario: Portsmouth Approach...
Custom scenario installed
=== Available Scenarios ===
a) Buoyage, ..., m) Portsmouth Approach Custom
=== Bridge Command setup complete ===
```

### Pre-task (task setup) - Key outputs
```
=== Setting up select_and_start_scenario task ===
Starting Bridge Command...
Bridge Command is running (PID XXXX)
=== Task setup complete ===
```

## Verification Checklist

- [x] Installation script completes without errors (built from source)
- [x] Setup script completes without errors
- [x] Bridge Command launcher is visible in screenshot
- [x] Application is in correct initial state (launcher with buttons)
- [x] Real data is loaded (14 scenarios including Portsmouth, Swinomish)
- [x] Custom scenario installed successfully
- [x] Task setup runs without errors
- [x] Task start state is correct (launcher visible, ready for agent)
- [x] Simulation loads and runs correctly (verified via scenario selection → load → run)
- [x] Settings editor accessible and functional (view_angle visible and editable)
- [x] Radar display works in simulation
- [x] Navigation lights visible in night scenario
