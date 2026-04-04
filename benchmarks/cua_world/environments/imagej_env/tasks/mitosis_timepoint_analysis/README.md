# Task: Mitosis Time-Lapse Quantification

## Domain Context

Time-lapse fluorescence microscopy allows cell biologists to observe and quantify dynamic cellular processes, including cell division (mitosis). Tracking how the number of mitotic cells and the total fluorescent area change over time provides quantitative data about cell cycle kinetics: how long cells spend in different mitotic stages, whether drug treatment arrests cells at a specific stage, and what fraction of the population is dividing at any given time.

Working with time-lapse data requires understanding multi-dimensional image stacks (hyperstacks) — datasets that have not just x and y dimensions but also z (depth), time (T), and channel (C) dimensions. A researcher must navigate these dimensions correctly, select the appropriate channel for the biological signal of interest, collapse the z-dimension using projection methods, and make consistent measurements at each time point.

This workflow is standard for:
- **Biochemists and Biophysicists** — characterizing drug effects on cell division
- **Nanosystems Engineers** — quantifying cell viability and division in toxicity assays

## Data Source

Fiji built-in sample: **Mitosis (5D stack)** (File > Open Samples > Mitosis (5D stack))

This is a real fluorescence time-lapse microscopy dataset of cells undergoing mitosis:
- **Dimensions**: 171 × 196 pixels, 2 channels, 51 z-slices, 5 time frames
- **Channel 1 (FITC/green)**: Labels the mitotic spindle
- **Channel 2 (DAPI/Hoechst/blue)**: Labels chromosomes/DNA
- **Time frames**: 5 sequential time points showing cells progressing through division

This is genuine experimental data, not a synthetic dataset.

## Goal

Create a time series of mitotic cell measurements by processing each time frame of the Mitosis 5D stack. Save the per-time-frame results to `~/ImageJ_Data/results/mitosis_timeseries.csv`.

The completed analysis must demonstrate:
1. Understanding that the data is a hyperstack with time and z dimensions
2. Appropriate handling of z-dimension (e.g., Z-projection per time frame)
3. Measurement at ≥4 distinct time frames (out of 5 available)
4. Cell count or fluorescent area measurement per time frame
5. Recognition that values change over time (temporal variation)

## Starting State

- Fiji is running and ready
- No images are pre-opened
- `~/ImageJ_Data/results/` exists and is empty
- Task start time recorded at `/tmp/task_start_timestamp`

## Success Criteria (100 points, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Result file created | 20 | File exists, non-empty, created after task start |
| Multiple time frames | 25 | At least 4 rows with distinct time frame indices |
| Measurements per frame | 25 | Cell count and/or total area column present with positive values |
| Temporal variation | 20 | Values in measurement column are not all identical across frames |
| Frame index column | 10 | A column identifying the time frame number or label |

## Output File Specification

**File:** `~/ImageJ_Data/results/mitosis_timeseries.csv`

Required columns (names may vary):
- Time frame index or identifier (T=1, T=2, ..., T=5)
- Cell/object count per frame
- Total thresholded fluorescent area per frame

Example format:
```
Frame,Cell_Count,Total_Area_px2
1,3,4820
2,4,6230
3,5,7890
4,5,7640
5,3,5120
```

## Verification Approach

The export script creates `/tmp/mitosis_timepoint_analysis_result.json`. The verifier checks:
1. File existence and timestamp
2. Row count >= 4 (measuring at least 4 of the 5 time frames)
3. Numeric measurement column (area or count) with positive values
4. Frame identifier column present
5. The measurement values are not all identical (genuine temporal variation)

## Anti-Gaming Measures

- Timestamp check: file must be created after task start
- Row count check: at least 4 rows required (cannot measure only 1 frame)
- Variation check: if all measurement values across frames are identical, score for that criterion = 0
- Values must be positive and non-zero

## Notes on Hyperstack Navigation

The Mitosis 5D stack has a complex structure that the agent must navigate. Key concepts:
- The stack opens as a hyperstack with slider controls for Z (slice), T (frame), and C (channel)
- The bottom sliders control which z-slice, time frame, and channel are displayed
- To collapse z: **Image > Stacks > Z Project** — but must first select the correct time frame and channel
- Alternatively, the agent might select a single representative z-slice at each time point
- The spindle channel (FITC, typically channel 1) or the chromosome channel (DAPI, channel 2) can be used

The agent must figure out the correct workflow for navigating and measuring the hyperstack. No specific UI steps are prescribed.
