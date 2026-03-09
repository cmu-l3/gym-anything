# QBlade Environment - Evidence Documentation

## Environment Summary
- **Application**: QBlade v0.96.2 64-bit (Community Edition)
- **Source**: SourceForge - QBlade_linux_v0.96.2_64bit.zip
- **Type**: Wind turbine design and BEM simulation desktop application
- **Base Image**: ubuntu-gnome-systemd_highres
- **Resources**: 4 CPU, 6GB RAM, networking enabled

## Tasks (10 total)

### Original Tasks (5)
1. **generate_naca_airfoil** - Generate NACA 4412 airfoil and export to .dat file
2. **import_airfoil_dat** - Import NACA 2412 airfoil, run XFoil polar analysis
3. **design_hawt_blade** - Design 10m HAWT blade with 5+ stations
4. **run_bem_simulation** - Run BEM simulation with TSR range 1-12
5. **load_sample_project** - Load/create project and save as .wpa

### New Hard Tasks (5) - Added 2026-02-23
6. **airfoil_polar_comparison** - Import 3 NACA airfoils (0015, 2412, 4412), run XFoil at Re=1M, export 3 polar files for comparison
7. **extrapolate_polar_360** - Import NACA 6412, run XFoil at Re=500k, extrapolate polar to 360 degrees, export
8. **multi_reynolds_analysis** - Import NACA 4412, run XFoil at 3 Reynolds numbers (200k, 500k, 1M), export 3 polars
9. **design_hawt_blade_multisection** - Import 2 airfoils, design 6+ station blade with tapering chord/twist, save .wpa project
10. **turbine_performance_evaluation** - Load NREL 5MW project, run BEM TSR sweep 1-15, export results + write performance report

## Test Results

### Environment Startup
- Startup time: ~62-74 seconds total
  - VM + install hooks: ~52-65s
  - Task-specific hooks: ~9s
- QBlade binary found at: `/opt/qblade/QBlade 64bit release linux/bin/QBlade`
- All shared libraries resolved (no "not found")
- QBlade window title: "QBlade v0.96.2 64bit"

### Interactive Task Completion (generate_naca_airfoil)
- Used ask_cua.py + xdotool to navigate QBlade GUI
- **Steps performed**:
  1. Clicked "Open Foil Design application" toolbar icon (window x=340, y=48)
  2. Opened Foil menu, navigated with keyboard arrows to "Naca Foils"
  3. Filled NACA dialog: digits=4412, panels=100
  4. Used Foil > Export to save as /home/ga/Documents/airfoils/generated_naca4412.dat
- **Verification result**: Score 100/100, reward=1.0
  - Generated airfoil file created (30 pts)
  - File contains coordinate data - 100 lines (30 pts)
  - File appears to be a NACA airfoil profile (20 pts)
  - Sufficient coordinate points - 100 lines (20 pts)

### Verification Pipeline Test (without agent work)
- **generate_naca_airfoil**: Score 0, "Generated airfoil file not found" (expected - no agent work)
- **load_sample_project**: Score 55, detected 4 new .wpa files and QBlade running (expected - no agent work, but sample projects copied)

### Data Files Verified
- 4 NACA airfoil .dat files from UIUC database in /home/ga/Documents/airfoils/
- 4 sample .wpa projects (NREL_5MW, NREL_PhaseVI, SANDIA_SERI-8, TUB_BeRTwpa) in /home/ga/Documents/projects/

## Evidence Files
- `qblade_running.png` - Screenshot of QBlade v0.96.2 running in VM
- `foil_design_module.png` - Foil Design module opened with toolbar visible
- `naca_dialog.png` - NACA Foils dialog with fields for digits and panels
- `naca_4412_generated.png` - Window capture showing NACA 4412 generated (12% thickness, 4% camber)
- `naca_generated.png` - Full screen after NACA 4412 generation
- `export_dialog.png` - Export Foil file save dialog

## New Tasks Testing Evidence (2026-02-23)

### Phase 4: Environment + Script Testing (Live VM)
All 5 new tasks were tested with live VM boot:
- All environments loaded successfully
- All setup scripts created expected `/tmp/initial_*` files
- All export scripts produced valid JSON with "Export Complete"
- QBlade confirmed running for all tasks
- Screenshots captured for each task starting state

### Phase 5: Verification Testing (Offline + Live)

**Do-Nothing Tests** (all 5 PASS):
| Task | Score | Passed | Result |
|------|-------|--------|--------|
| airfoil_polar_comparison | 0 | False | No polar files found |
| extrapolate_polar_360 | 0 | False | File not found |
| multi_reynolds_analysis | 0 | False | All 3 polars not found |
| design_hawt_blade_multisection | 0 | False | Project file not found |
| turbine_performance_evaluation | 0 | False | No output files (gate) |

**Partial Completion Tests** (all 5 PASS - scores between 0 and threshold):
| Task | Score | Passed | Scenario |
|------|-------|--------|----------|
| airfoil_polar_comparison | 60 | False | 2/3 polars, one sparse |
| extrapolate_polar_360 | 68 | False | XFoil data only, no 360° |
| multi_reynolds_analysis | 60 | False | 2/3 Reynolds polars |
| design_hawt_blade_multisection | 69 | False | Sample copy detected |
| turbine_performance_evaluation | 55 | False | BEM only, no report |

**Full Completion Tests** (all 5 PASS - score=100):
All 5 tasks return score=100, passed=True with simulated complete results.

### Verifier Fix Applied
- **turbine_performance_evaluation**: Added gate — if neither BEM file nor report file exists, return score=0 immediately. This prevents the "QBlade running" criterion (10 pts) from inflating do-nothing scores.

### Evidence Files (New Tasks)
- `airfoil_polar_comparison_screenshot.png` - Starting state with 3 airfoil files
- `extrapolate_polar_360_screenshot.png` - Starting state with only NACA 6412
- `multi_reynolds_analysis_screenshot.png` - Starting state with only NACA 4412
- `design_hawt_blade_multisection_screenshot.png` - Starting state with 2 airfoil files
- `turbine_performance_evaluation_screenshot.png` - Starting state with sample projects
- `*_evidence.json` - Detailed evidence JSON for each task
- `new_tasks_test_summary.json` - Complete Phase 4+5 live VM test results
- `verifier_offline_tests.json` - Offline verifier tests (do-nothing, partial, full)

## Key Issues Discovered and Fixed
1. **libQGLViewer permissions**: Bundled .so had `-rwxr-x--x` (no read for others), fixed with chmod 755
2. **Bundled libstdc++ conflict**: Old GCC 4.x libstdc++ broke Qt5 (missing CXXABI_1.3.9), fixed by removing it
3. **Qt5 dependencies**: Must explicitly install libqt5opengl5, libqt5widgets5, etc.
4. **Project file format**: QBlade v0.96 uses `.wpa` not `.qpr`
5. **Sample projects directory**: Named "sample projects" (lowercase, with space) not "SampleProjects"
6. **Launch command**: Must use `export DISPLAY=:1;` with semicolons in `su - ga -c` (not space-separated env vars)
