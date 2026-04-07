# openvsp_vspaero_polar

## Task Description

An aerodynamicist at a research lab must generate a drag polar for the eCRM-001 wing-body configuration using OpenVSP's built-in panel method solver (VSPAero). This task requires understanding aerodynamic analysis workflow, setting up a parametric alpha sweep, and post-processing the results to identify the aerodynamic optimum.

**Realistic context**: Generating lift/drag polars is one of the most common tasks in conceptual aerodynamics. Engineers use VSPAero for rapid preliminary analysis before committing to higher-fidelity CFD. This task combines OpenVSP GUI navigation, VSPAero setup, result interpretation, and report generation — a complete mini-workflow.

## What the Agent Must Do

1. Open `/home/ga/Documents/OpenVSP/eCRM-001_wing_tail.vsp3` in OpenVSP
2. Navigate to Analysis > VSPAero (or Analysis menu)
3. Set up a Vortex Lattice Method (VLM) sweep:
   - Alpha range: -2° to +10° (at least 7 points)
   - Mach: 0.2
   - Standard sea-level conditions
4. Run the analysis
5. Parse the `.polar` output file (located in the vspaero output directory)
6. Compute L/D = CL / CDtot at each alpha
7. Find the alpha at maximum L/D
8. Write `/home/ga/Desktop/vspaero_report.txt` with the L/D table and maximum

## Expected Output

```
VSPAero Polar Analysis - eCRM-001
Alpha sweep: -2 to 10 deg, Mach 0.2

Alpha(deg)  CL        CDtot     L/D
-2.0        ...       ...       ...
0.0         ...       ...       ...
2.0         ...       ...       ...
...

Maximum L/D: XX.X at alpha = Y.Y deg
```

## Scoring (100 pts)

- Report file exists: 10 pts
- Report contains numeric L/D value in [5, 30]: 25 pts
- Report contains stated alpha at max L/D in [-2, 12]: 25 pts
- Polar file exists with ≥7 data rows: 40 pts

Pass threshold: 60.

## Files

- `setup_task.sh` — copies eCRM model, clears old vspaero results, creates Desktop directory
- `export_result.sh` — finds .polar file, captures content and report text
- `verifier.py` — checks polar row count, report content, and L/D numeric range

## Difficulty Justification

**very_hard**: Requires navigating VSPAero sub-panels, configuring solver parameters, running the analysis (potentially slow), locating the output file, parsing tabular data, computing derived metrics (L/D), and writing a structured report — all within a single session. High cognitive load and many failure points.
