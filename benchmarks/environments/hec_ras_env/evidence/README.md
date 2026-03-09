# HEC-RAS Environment Evidence Documentation

## Environment Overview
- **Application**: HEC-RAS 6.6 (Hydrologic Engineering Center's River Analysis System)
- **Developer**: U.S. Army Corps of Engineers (USACE)
- **Base Image**: ubuntu-gnome-systemd_highres (1920x1080)
- **Resources**: 4 CPU, 6GB RAM
- **Data**: Official USACE Muncie, Indiana flood model example project (real data)

## Installation Verification

### Pre-start Hook Output (install_hec_ras.sh)
- Downloaded HEC-RAS 6.6 Linux build (213 MB) from USACE servers
- Extracted executables: RasUnsteady, RasSteady, RasGeomPreprocess
- Installed Intel Fortran runtime libraries (MKL, OpenMP, etc.)
- Installed Python packages: h5py, numpy, matplotlib, pandas, scipy, rashdf
- All library dependencies resolved (verified via ldd)

### Post-start Hook Output (setup_hec_ras.sh)
- Copied Muncie example project to /home/ga/Documents/hec_ras_projects/Muncie/
- Copied input files from wrk_source/ to working directory:
  - Muncie.x04 (115 KB) - Geometry preprocessor input (1758 lines, cross sections)
  - Muncie.b04 (3.6 KB) - Boundary conditions (flow hydrograph, computation parameters)
  - Muncie.r04 (745 KB) - Steady flow input (10582 lines)
  - Muncie.p04.tmp.hdf (4.2 MB) - Template HDF5 for simulation
- Deployed Python analysis scripts
- Configured gedit with line numbers and syntax highlighting
- All executables in PATH, libraries in LD_LIBRARY_PATH

## Simulation Verification

### RasUnsteady Simulation Run
- **Command**: `RasUnsteady Muncie.p04.tmp.hdf x04`
- **Duration**: ~60 seconds
- **Result**: Successful completion with "Finished Unsteady Flow Simulation"
- **Output**: Muncie.p04.tmp.hdf grew from 4.2 MB to 16.7 MB
- **Volume Error**: -2.157 acre-feet (0.006%) - excellent accuracy
- **Results**: 289 timesteps, 5765 computational cells (2D flow area)

### Python Analysis Script Results
- **Peak WSE**: 953.840 ft (overall), 946.104 ft (mean peak across all cells)
- **Most Dynamic Cell**: Cell 537 with 20.24 ft flood range (925-945 ft)
- **CSV Export**: Successfully written to peak_wse_results.csv

### Flood Hydrograph Plot
- See `task5_hydrograph_plot.png` for the matplotlib plot
- Shows classic flood wave pattern with rising limb and peak at 945.23 ft

## Task Start State Verification (via visual_grounding MCP tool)

All 5 task start states verified interactively using the `visual_grounding` MCP tool on live VM screenshots. Each terminal-based task shows a distinct file listing so screenshots are visually distinguishable.

### Task 1: edit_mannings_roughness
- **Screenshot**: `task1_mannings_data_visible.png`
- **Start State**: gedit open with Muncie.x04, maximized, line numbers visible
- **visual_grounding confirmation**:
  - "Muncie.x04" visible in title bar
  - "Section - XS Manning's/Roughness Data" highlighted in orange at lines 58 and 87
  - Manning's roughness values .04 and .07 visible at line 60
  - Cursor positioned at line 58 (first match)
- **Completability**: Agent must navigate to the Manning's roughness section, identify the main channel n-value (middle coefficient), and change it to 0.05. The file contains many numeric values for geometry coordinates that look similar, so the agent must understand the section structure.

### Task 2: run_unsteady_simulation
- **Screenshot**: `task2_files_and_executables.png`
- **Start State**: gnome-terminal in Muncie directory with auto-listed project files and executables
- **visual_grounding confirmation**:
  - "=== Muncie Project Files ===" header visible
  - 4 project files listed: Muncie.b04 (3.6KB), Muncie.p04.tmp.hdf (4.1MB), Muncie.r04 (728KB), Muncie.x04 (114KB)
  - "=== HEC-RAS Executables ===" header visible
  - 3 executables: RasGeomPreprocess, RasSteady, RasUnsteady
- **Completability**: Agent must examine available files and executables, determine that RasUnsteady is the correct solver for unsteady flow, figure out the correct arguments (HDF template file + geometry extension), run the simulation, and rename the output.

### Task 3: analyze_peak_wse
- **Screenshot**: `task3_results_and_scripts.png`
- **Start State**: gnome-terminal in Muncie directory with auto-listed simulation results and analysis scripts
- **visual_grounding confirmation**:
  - "=== Simulation Results ===" header visible
  - Muncie.p04.hdf (16M) clearly listed — confirms simulation output exists
  - Muncie.p04.tmp.hdf (16M) also listed
  - "=== Analysis Scripts ===" header visible
  - 3 scripts listed: analyze_peak_wse.py, export_results_csv.py, plot_flood_hydrograph.py
- **Completability**: Agent must identify the correct analysis script, determine its usage (by reading the script or running without args), construct the command with appropriate HDF input and CSV output path. Demonstrated end-to-end: script produces Peak WSE 953.040, CSV saved successfully.

### Task 4: modify_flow_boundary
- **Screenshots**: `task4_boundary_start.png`, `task4_flow_21000_visible.png`
- **Start State**: gedit open with Muncie.b04, maximized
- **visual_grounding confirmation**:
  - "Muncie.b04" visible in title bar
  - "Upstream Flow Hydrograph - River: White Reach: Muncie RS: 15696.24" visible
  - Peak flow value 21000 highlighted in orange at lines 79-80
  - 21000 appears 5 consecutive times (time steps 16-20) representing sustained peak
- **Completability**: Agent must find the flow hydrograph section, identify and replace all occurrences of the peak flow 21000 with 25200 (20% increase), and save.

### Task 5: plot_flood_hydrograph
- **Screenshots**: `task5_results_and_plotscripts.png`, `task5_hydrograph_plot.png`
- **Start State**: gnome-terminal in Muncie directory with auto-listed simulation results, plotting scripts, and empty output directory
- **visual_grounding confirmation**:
  - "=== Simulation Results ===" shows Muncie.p04.hdf (16M) — confirms results exist
  - "=== Plotting Scripts ===" shows plot_flood_hydrograph.py
  - "=== Output Directory ===" shows empty (no plots yet)
- **Completability**: Agent must identify the plotting script, determine usage, construct command with HDF input and PNG output path. Demonstrated end-to-end: matplotlib plot shows "Flood Hydrograph - 2D Interior Area", Cell 537 with 20.24 ft range, peak WSE 945.23 ft.

## Real Data Source
- **Muncie Example Project**: Official USACE test dataset included with HEC-RAS 6.6 Linux build
- **Location**: Muncie, Indiana (White River)
- **Model Type**: 2D unsteady flow with 5765 computational cells
- **Hydrograph**: 24-hour flood event with peak flow of 21,000 cfs
- **Grid**: 50-foot resolution user-defined n-value regions
- **Source URL**: https://www.hec.usace.army.mil/software/hec-ras/downloads/Linux_RAS_v66.zip

## Final Clean Test (2026-02-24)

### Fresh Start Verification
A completely fresh environment start (no cached checkpoints) was executed for task 3 (analyze_peak_wse).

**Verification Checklist - ALL PASSED:**
- [x] 3/3 executables found in PATH (RasUnsteady, RasSteady, RasGeomPreprocess)
- [x] 0 missing libraries (all Intel Fortran/MKL/OpenMP resolved)
- [x] 4/4 project files present (Muncie.x04, .b04, .r04, .p04.tmp.hdf)
- [x] 3/3 analysis scripts deployed (analyze_peak_wse.py, plot_flood_hydrograph.py, export_results_csv.py)
- [x] All Python packages confirmed (h5py, numpy, matplotlib, pandas)
- [x] Terminal window open in correct directory (~/Documents/hec_ras_projects/Muncie)
- [x] No errors in pre_start or post_start logs
- [x] "All libraries resolved" confirmed

**Screenshot**: `final_clean_test.png` - Terminal showing full verification output: 3 executable paths, "Missing: 0" libraries, 4 project files with sizes, 3 analysis scripts, Python "All OK", and "ALL CHECKS PASSED"

## Evidence Files

| File | Description |
|------|-------------|
| `task1_mannings_data_visible.png` | Task 1: gedit with Manning's n values highlighted at lines 58/87 |
| `task2_files_and_executables.png` | Task 2: Terminal showing project files AND HEC-RAS executables listed |
| `task3_results_and_scripts.png` | Task 3: Terminal showing Muncie.p04.hdf (16M) AND 3 analysis scripts listed |
| `task3_analysis_results.png` | Task 3: End-to-end proof — analysis script output with peak WSE and CSV |
| `task4_boundary_start.png` | Task 4: gedit with Muncie.b04 open (boundary conditions) |
| `task4_flow_21000_visible.png` | Task 4: Peak flow 21000 highlighted in flow hydrograph section |
| `task5_results_and_plotscripts.png` | Task 5: Terminal showing simulation results, plot script, empty output dir |
| `task5_hydrograph_plot.png` | Task 5: End-to-end proof — matplotlib flood hydrograph plot |
| `final_clean_test.png` | Final clean test: Terminal in Muncie directory after fresh start |
