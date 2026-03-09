# GMAT Environment Evidence Documentation

## Environment Overview
- **Application**: NASA GMAT (General Mission Analysis Tool) R2022a
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 6GB RAM, Network enabled
- **Tasks**: 2 tasks (modify_hohmann_transfer, add_ground_track_plot)

## Verification Checklist

### Installation Script (pre_start)
- [x] GMAT R2022a downloaded from SourceForge (~370MB tarball)
- [x] Extracted and binaries placed at `/opt/GMAT/bin/`
- [x] GUI binary: `/opt/GMAT/bin/GMAT-R2022a` (ELF 64-bit)
- [x] Console binary: `/opt/GMAT/bin/GmatConsole`
- [x] 160 sample .script files available in `/opt/GMAT/samples/`
- [x] System dependencies (Mesa/OpenGL, X11 libs) installed
- [x] Python lxml installed for verification
- [x] gmatcentral.org blocked in /etc/hosts (prevents Firefox opening)

**Pre-start log excerpt (from actual test run):**
```
=== Installing NASA GMAT (General Mission Analysis Tool) ===
Trying GMAT R2022a from SourceForge...
Downloaded R2022a successfully
=== Extracting GMAT ===
Found GMAT root at: /tmp/gmat_extract/GMAT/R2022a
Found GMAT GUI binary: /opt/GMAT/bin/GMAT-R2022a
Found GMAT Console binary: /opt/GMAT/bin/GmatConsole
Found 160 sample .script files
=== GMAT installation complete ===
```

### Setup Script (post_start)
- [x] Environment variables configured (GMAT_ROOT, PATH, LD_LIBRARY_PATH)
- [x] 160 sample missions copied to `/home/ga/Documents/missions/`
- [x] Launcher script created at `/home/ga/launch_gmat.sh`
- [x] Desktop shortcut created
- [x] gmatcentral.org blocked to prevent Firefox launch
- [x] Warm-up launch successful (GMAT window appeared after 2 seconds)
- [x] Firefox killed after warm-up

**Post-start log excerpt (from actual test run):**
```
=== Setting up GMAT ===
GMAT GUI binary: /opt/GMAT/bin/GMAT-R2022a
GMAT Console binary: /opt/GMAT/bin/GmatConsole
Copied 160 sample missions
=== Performing warm-up launch of GMAT ===
GMAT window appeared after 2 seconds
GMAT warm-up launch complete
=== GMAT Setup Summary ===
GMAT root: /opt/GMAT
GUI binary: /opt/GMAT/bin/GMAT-R2022a
Console binary: /opt/GMAT/bin/GmatConsole
Sample missions: 160 scripts
=== GMAT setup complete ===
```

### Task 1: modify_hohmann_transfer
- [x] Hohmann Transfer sample script found and copied
- [x] Keplerian orbital elements injected (SMA=6678.14, ECC=0.001, INC=28.5)
- [x] Script loaded and synchronized in GMAT
- [x] Window title: `HohmannTransfer_task.script - General Mission Analysis Tool (GMAT)`
- [x] Resources tree visible with DefaultSC, TOI, GOI, DefaultProp, OpenGLPlot1
- [x] No Firefox window visible
- [x] Script grep confirms `GMAT DefaultSC.SMA = 6678.14;` on line 15
- **Evidence**: `task1_initial_state.png`

**Task 1 verified via visual_grounding MCP tool:**
- GMAT open with Hohmann Transfer script loaded
- GUI/Script Sync Status: "Synchronized" (green)
- Resources tree shows: DefaultSC, Burns (TOI, GOI), DefaultProp, OpenGLPlot1
- Console: "Successfully interpreted the script"
- No unwanted windows visible

### Task 2: add_ground_track_plot
- [x] LEO Propagation script created with real orbital parameters (ISS-like)
- [x] Script loaded and synchronized in GMAT
- [x] Window title: `LEO_Propagation.script - General Mission Analysis Tool (GMAT)`
- [x] Resources tree shows LEO_Sat, LEOProp, DefaultOrbitView
- [x] No GroundTrackPlot present (agent must add one)
- [x] Script grep confirms 0 occurrences of "GroundTrackPlot"
- [x] No Firefox window visible
- **Evidence**: `task2_initial_state.png`

**Task 2 verified via visual_grounding MCP tool:**
- GMAT open with LEO_Propagation script loaded
- GUI/Script Sync Status: "Synchronized" (green)
- Resources tree shows: LEO_Sat, LEOProp, DefaultOrbitView (no GroundTrackPlot)
- Console: "Successfully interpreted the script"
- No unwanted windows visible

## Screenshots
- `task1_initial_state.png` - GMAT with Hohmann Transfer script loaded, showing Resources tree with DefaultSC (SMA=6678.14 km), burns (TOI, GOI), propagator, and OpenGLPlot1. Console confirms "Successfully interpreted the script".
- `task2_initial_state.png` - GMAT with LEO Propagation script loaded, showing Resources tree with LEO_Sat, LEOProp propagator, and DefaultOrbitView (no GroundTrackPlot). Console confirms "Successfully interpreted the script".

## Real Data Used
- **Hohmann Transfer**: Based on GMAT's official sample `Ex_HohmannTransfer.script` (real NASA mission scenario), augmented with explicit Keplerian orbital elements: SMA=6678.14 km (300 km LEO), ECC=0.001, INC=28.5 deg
- **LEO Propagation**: Uses ISS-like orbital elements: SMA=6878.14 km (500 km altitude), INC=28.5 deg, ECC=0.001
- All 160 sample scripts are official NASA-provided mission scenarios included with GMAT

## Timing (from actual test run)
- Full environment setup (fresh, no cache): ~4-8 minutes
  - GMAT download: ~3-4 minutes (370MB from SourceForge)
  - Package install + extraction: ~2 minutes
  - Post-start (warm-up launch): ~1 minute
  - Task setup: ~16 seconds
