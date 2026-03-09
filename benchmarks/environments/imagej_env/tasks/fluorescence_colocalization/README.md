# Task: Fluorescence Colocalization Analysis

## Domain Context

Fluorescence colocalization analysis is a core technique in cell and molecular biology. When two proteins are labeled with different fluorescent markers (e.g., a red dye on protein A and a green dye on protein B), measuring the spatial overlap between their signals reveals whether the two proteins occupy the same cellular compartments — indicating potential direct interaction, shared trafficking pathways, or co-recruitment to the same structures.

Quantitative colocalization goes beyond simply observing visual overlap; it requires computing metrics such as the Pearson correlation coefficient (r), Manders' overlap coefficients (M1, M2), or intersection-over-union (IoU) that can be compared across conditions, time points, or drug treatments. This analysis is routinely performed by biochemists and cell biologists working on signal transduction, vesicle trafficking, organelle identity, and protein-protein interaction studies.

The primary occupations using this workflow (by economic impact):
- **Nanosystems Engineers** — quantifying co-distribution of nanoparticle labels
- **Biochemists and Biophysicists** — co-localization of signaling proteins, receptors, and organelle markers

## Data Source

Fiji built-in sample: **Fluorescent Cells** (File > Open Samples > Fluorescent Cells)

This is a real fluorescence microscopy image of mammalian cells stained with three fluorescent dyes:
- **Red channel** (rhodamine): marks a specific cellular compartment
- **Green channel** (FITC): marks a different but partially overlapping compartment
- **Blue channel** (DAPI): marks nuclei

The image is a real experimental acquisition, not a synthetic dataset.

## Goal

Perform a complete quantitative colocalization analysis between the red and green fluorescence channels and save the results to `~/ImageJ_Data/results/colocalization_results.csv`.

The completed analysis must demonstrate that the agent:
1. Successfully split the RGB image into separate channels
2. Thresholded each channel to define signal regions
3. Measured the area and mean intensity of each channel's thresholded region
4. Quantified the pixel-level overlap between the two channels
5. Computed at least one standard colocalization coefficient

## Starting State

- Fiji is running and ready
- No images are pre-opened; the agent must open the Fluorescent Cells sample
- Results directory `~/ImageJ_Data/results/` exists and is empty
- Task start time is recorded at `/tmp/task_start_timestamp`

## Success Criteria (100 points, pass at 60)

| Criterion | Points | Description |
|-----------|--------|-------------|
| Result file created | 25 | `colocalization_results.csv` exists, is non-empty, created after task start |
| Red channel data | 25 | Area and/or mean intensity of red channel present in output |
| Green channel data | 25 | Area and/or mean intensity of green channel present in output |
| Colocalization metric | 25 | Pearson r, Manders M1/M2, overlap coefficient, or IoU present with value in [0,1] |

## Output File Specification

**File:** `~/ImageJ_Data/results/colocalization_results.csv`

The CSV should contain at minimum:
- A column identifying the channel (red, green, or names like "Channel 1")
- Area measurement for each channel's thresholded region
- Mean intensity for each channel within its thresholded region
- A colocalization metric (any one of: Pearson r, M1, M2, overlap coefficient, percent overlap)

Example format (any layout that captures these values is acceptable):
```
Channel,Area_px,Mean_Intensity,Colocalization_Metric,Metric_Value
Red,12450,87.3,Pearson_r,0.62
Green,18920,95.1,Manders_M1,0.71
Overlap,8340,,,
```

## Verification Approach

The export script (`export_result.sh`) reads the CSV and creates a structured JSON at `/tmp/fluorescence_colocalization_result.json`. The verifier (`verifier.py::verify_fluorescence_colocalization`) copies this JSON from the VM and checks:
1. File existence and modification timestamp (must be after task start)
2. Presence of red-channel keywords in columns or values
3. Presence of green-channel keywords in columns or values
4. Presence of colocalization metric keywords (pearson, manders, overlap, coloc, correlation, m1, m2)
5. Numeric values in biologically plausible ranges

## Anti-Gaming Measures

- The result file path is checked against the task start timestamp — pre-existing files score zero
- Content must include recognizable channel labels and colocalization terminology
- A file containing only arbitrary numbers with no contextual labels does not pass
