# PyMOL Environment - Evidence Documentation

## Environment Overview

- **Application**: PyMOL Molecular Graphics System v2.5.0 (Open-Source)
- **Base Image**: ubuntu-gnome-systemd_highres
- **Installation**: `apt-get install -y pymol python3-pymol python3-pyqt5`
- **Resources**: 4 CPU, 6GB RAM, no GPU required
- **Real Data**: 3 PDB structures from RCSB Protein Data Bank (4HHB, 1UBQ, 1CRN)

## Installation Verification

### PyMOL Installation
```
$ which pymol
/usr/bin/pymol

$ pymol --version
PyMOL 2.5.0 Open-Source, 2022-03-17

$ dpkg -l | grep pymol
ii  pymol           2.5.0+dfsg-1build1  all    Molecular Graphics System
ii  pymol-data      2.5.0+dfsg-1build1  all    data files for PyMOL
ii  python3-pymol   2.5.0+dfsg-1build1  amd64  Molecular Graphics System (Python 3 modules)
```

### Real PDB Data Downloaded
All structures from https://files.rcsb.org/download/:
```
$ ls -la /opt/pymol_data/structures/
-rwxr-xr-x 1 root root  49491 1CRN.pdb   (Crambin - 46 residues)
-rwxr-xr-x 1 root root  78570 1UBQ.pdb   (Ubiquitin - 76 residues)
-rwxr-xr-x 1 root root 473769 4HHB.pdb   (Hemoglobin tetramer - 4 chains)
```

### Supporting Tools
```
$ which xdotool wmctrl scrot
/usr/bin/xdotool
/usr/bin/wmctrl
/usr/bin/scrot

$ python3 -c 'import Bio; print(Bio.__version__)'
1.86
```

## Setup Script Verification

The `setup_pymol.sh` script:
1. Creates user config directories and copies PDB files to `/home/ga/PyMOL_Data/structures/`
2. Creates `.pymolrc` with default settings
3. Creates desktop shortcut and launch script
4. Performs warm-up launch to clear first-run state
5. Warm-up launch successfully detected PyMOL window (`0x0080000a`)

## Task Verification

### Task 1: color_protein_by_chain (Easy)

**Description**: The agent must switch to cartoon representation and color each chain of hemoglobin (4HHB) a distinct color (A=red, B=green, C=blue, D=yellow). The agent must determine the correct PyMOL commands to achieve this.

**Start State** (`task1_color_protein_start_state.png`):
- PyMOL is open with 4HHB hemoglobin loaded
- Structure visible in default representation
- Command line available with `PyMOL>` prompt

**Completability Evidence** (`task1_cartoon_representation.png`, `task1_color_chains_completed.png`):
- `show cartoon` command changes representation to ribbon/helix view
- Chain coloring commands assign distinct colors to each subunit
- Final zoomed-out screenshot shows all 4 chains distinctly colored: red (chain A, lower right), green (chain B, upper right), blue (chain C, upper left), yellow (chain D, left) — all clearly visible from an oriented perspective using `orient` + `zoom complete=1`

### Task 2: measure_atomic_distance (Medium)

**Description**: The agent must create a distance measurement object called `dist_NC` between the CA atoms of MET1 and GLY76 in ubiquitin (1UBQ). The agent must figure out PyMOL's atom selection syntax and the `distance` command on its own. Task setup uses a `.pml` script (not xdotool) to reliably set cartoon representation before the agent starts.

**Start State** (`task2_measure_distance_start_state.png`):
- PyMOL is open with 1UBQ loaded in cartoon representation
- Characteristic beta-grasp fold of ubiquitin visible
- Command line available

**Completability Evidence** (`task2_measure_distance_completed.png`):
- Distance object `dist_NC` successfully created
- Measured distance: 3.71 Angstroms (correct for ubiquitin's compact fold)
- Yellow dashed line with distance label visible on structure

### Task 3: ray_trace_protein_image (Hard)

**Description**: The agent must produce a publication-quality ray-traced PNG of crambin (1CRN) with specific requirements: cartoon representation, secondary structure coloring, white background, 1920x1080 resolution. The agent must determine the correct commands for representation, coloring by secondary structure type, background setting, ray tracing, and file export.

**Start State** (`task3_raytrace_start_state.png`):
- PyMOL is open with 1CRN crambin loaded
- Structure visible in default representation
- Output directory exists and is empty (clean state)

**Completability Evidence** (`task3_raytrace_completed.png`):
- Red helices, yellow sheets, green loops visible in cartoon mode
- White background applied
- Ray tracing at 1920x1080 completed (~15 seconds)
- Output PNG (170KB) saved to `/home/ga/PyMOL_Data/images/crambin_raytrace.png`
- Publication-quality rendering with smooth anti-aliased surfaces and proper lighting

## Testing Date
2026-03-02
