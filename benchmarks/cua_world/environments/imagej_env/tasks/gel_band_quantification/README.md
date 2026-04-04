# Task: Gel Electrophoresis Band Quantification

## Domain Context

Gel densitometry is one of the most common quantitative techniques in biochemistry. After running a Western blot or DNA gel, researchers must measure the intensity of each band to determine relative protein or nucleic acid amounts across experimental conditions. The correct workflow requires: (1) defining lane boundaries, (2) generating intensity profiles along each lane, (3) subtracting background (the rolling-ball or straight-line baseline subtraction), and (4) measuring the integrated optical density (area under each peak in the profile) as a proxy for molecular abundance.

A critical step that distinguishes expert from novice analysis is proper background subtraction — without it, systematic differences in gel staining uniformity will confound the measurements. Relative quantification (expressing each band as a percentage of the strongest band or a reference lane) normalizes for loading differences.

This workflow is used daily by:
- **Biochemists and Biophysicists** — quantifying protein expression, post-translational modifications, protein-protein interactions
- **Nanosystems Engineers** — characterizing nanoparticle synthesis yield, purity, and size distribution via gel analysis

## Data Source

Fiji built-in sample: **Gel** (File > Open Samples > Gel)

This is a real gel electrophoresis image showing multiple lanes with bands of varying intensities. The Fiji Gel sample is derived from an actual experimental gel photograph and is used as the canonical teaching example for gel analysis in ImageJ documentation.

## Goal

Quantify band intensities across all lanes in the gel image and express results as relative percentages. Save the quantification table to `~/ImageJ_Data/results/gel_quantification.csv`.

The completed analysis must demonstrate that the agent:
1. Identified and selected all distinct lanes in the gel
2. Generated lane intensity profiles with background correction
3. Measured integrated intensity for each band
4. Normalized band intensities to the strongest band in its lane
5. Saved a properly formatted results table

## Starting State

- Fiji is running and ready
- No images are pre-opened
- `~/ImageJ_Data/results/` exists and is empty
- Task start time recorded at `/tmp/task_start_timestamp`

## Success Criteria (100 points, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Result file created | 20 | File exists, non-empty, created after task start |
| Multiple measurements | 25 | At least 3 rows of band/measurement data |
| Intensity values present | 25 | Positive numeric intensity values in the data |
| Relative normalization | 15 | Values between 0–100 (percent) or 0–1 (fraction) present in a column |
| Multiple lanes | 15 | At least 2 distinct lane identifiers or position groups in the data |

## Output File Specification

**File:** `~/ImageJ_Data/results/gel_quantification.csv`

Required information (column names may vary):
- Lane identifier (lane number or name)
- Band position (y-coordinate or peak position in pixels)
- Integrated intensity or area under profile (background-corrected)
- Relative intensity as percentage of strongest band

Example format:
```
Lane,Band_Position_px,Integrated_Intensity,Relative_Intensity_pct
1,45,12450.3,100.0
1,112,8923.1,71.7
2,44,10230.5,82.2
2,113,7412.0,59.5
```

## Verification Approach

The export script creates `/tmp/gel_band_quantification_result.json`. The verifier checks:
1. File existence and timestamp
2. Row count >= 3
3. Presence of positive numeric intensity values
4. Presence of normalized values (0–100 range for percent, or 0–1 for fraction)
5. Evidence of multiple lanes

## Anti-Gaming Measures

- File modification time compared to task start timestamp
- Row count must be >= 3 (single-row output cannot represent a real gel analysis)
- Intensity values must be positive (zero or negative values fail)
- Must have both raw and normalized values (not just one column of identical percentages)

## Notes on ImageJ Gel Analysis Workflow

ImageJ's gel analysis tools are accessed via **Analyze > Gels**. The workflow is:
1. Draw a rectangular selection around the first lane → **Analyze > Gels > Select First Lane**
2. Move selection to next lane → **Analyze > Gels > Select Next Lane** (repeat for each lane)
3. **Analyze > Gels > Plot Lanes** — generates profile plots with background subtraction
4. In the plot window, use wand tool to select peak areas — or **Analyze > Gels > Label Peaks**
5. Results appear in the Results table with integrated intensities

The agent must figure out this workflow; the exact UI steps are not prescribed.
