# openvsp_degengeom_analysis

## Task Description

A structural analysis engineer needs to extract wing planform geometry data from the eCRM-001 model for use in a thin-shell finite element model. The task requires running OpenVSP's Degen Geom (Degenerate Geometry) tool, exporting the CSV results, parsing the wing geometry data, and writing a structured report.

**Realistic context**: Degen Geom is a standard pre-processing step in aerospace analysis pipelines. Structural engineers receive geometry data from the aerodynamics group in this format to set up shell element mesh parameterization. The engineer must understand what the CSV contains and extract the right quantities.

## What the Agent Must Do

1. With eCRM-001 model open, navigate to Analysis > Degen Geom
2. Configure export path to `/home/ga/Documents/OpenVSP/exports/eCRM001_degengeom.csv`
3. Run the Degen Geom analysis (click Compute or Execute)
4. Parse the resulting CSV to find the Wing component data
5. Extract: wingspan, planform area, MAC, aspect ratio
6. Write `/home/ga/Desktop/degengeom_report.txt` with labeled values in metric units

## Expected Report Format

```
Degen Geom Analysis Report - eCRM-001 Wing
==========================================
Component: Wing

Projected Wingspan   :  XX.XX m
Planform Area        :  XX.XX m^2
Mean Aerodynamic Chord: X.XX m
Aspect Ratio         :  X.XX
```

## Scoring (100 pts)

- Degen Geom CSV exported to correct path: 30 pts
- Report file exists with wing geometry content: 15 pts
- Report contains wingspan value in [5, 20] m: 20 pts
- Report contains aspect ratio in [4, 20]: 20 pts
- Report contains MAC value in [0.5, 5] m: 15 pts

Pass threshold: 60.

## Files

- `setup_task.sh` — copies eCRM model, clears stale DegenGeom outputs, launches OpenVSP
- `export_result.sh` — checks CSV existence, reads first lines, reads report
- `verifier.py` — validates CSV format and parses report for numeric values

## Difficulty Justification

**hard**: Requires knowing that Degen Geom is under the Analysis menu (not File > Export), configuring the export path, running the solver, then parsing the CSV format and extracting specific planform quantities. More advanced than single-step GUI tasks but does not require external domain knowledge beyond basic aerodynamics.
