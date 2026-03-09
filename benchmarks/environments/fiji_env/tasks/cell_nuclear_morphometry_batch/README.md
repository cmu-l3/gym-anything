# Task: cell_nuclear_morphometry_batch

## Overview

**Role**: Biological Technician / Medical Scientist
**Difficulty**: Very Hard
**Timeout**: 900 seconds (15 minutes), 90 max steps

You are a biological technician processing a batch of fluorescence microscopy images from a drug treatment experiment on Drosophila Kc167 cells. Your goal is to automate the segmentation and morphometry analysis of cell nuclei across all images in the dataset, producing a consolidated quantitative report.

---

## Dataset: BBBC008

**Source**: Broad Bioimage Benchmark Collection, dataset BBBC008
**URL**: https://data.broadinstitute.org/bbbc/BBBC008/
**Cell line**: Drosophila Kc167 cells
**Staining**: 2-channel fluorescence
- Channel w1 (DAPI): Nuclear DNA — these are the images you process
- Channel w2 (Fibrillarin): Nucleolus marker (not required for this task)

**Image format**: 16-bit grayscale TIFF
**Number of fields**: Multiple (typically 12+ fields of view)
**Location**: `~/Fiji_Data/raw/bbbc008/`

**Pixel scale**: 0.3296 µm/pixel
- Microscope: Nikon TE2000, 40x dry objective, NA 0.75
- Camera: CoolSNAP HQ (6.45 µm pixel size), 2x2 binning
- Effective scale: 6.45 / 40 × 2 = 0.3296 µm/pixel
- Documented in: `~/Fiji_Data/raw/bbbc008/scale_info.txt`

---

## Analysis Pipeline

For each DAPI image (filenames containing `w1`):

1. **Background Subtraction**: Apply Subtract Background with Rolling Ball radius = 50 pixels
   `Process > Subtract Background... → Rolling Ball Radius: 50`

2. **Thresholding**: Apply automatic threshold to segment nuclei from background
   `Image > Adjust > Auto Threshold` (Otsu, Triangle, or similar method)
   Convert to binary mask.

3. **Watershed Separation**: Separate touching nuclei
   `Process > Binary > Watershed`

4. **Particle Analysis**: Measure individual nuclei
   `Analyze > Analyze Particles...`
   - Size: 50-5000 pixels² (exclude debris < 50 and clumps > 5000)
   - Circularity: 0.0-1.0
   - Show: Outlines (for QC overlay)
   - Measurements: Area, Perimeter, Circularity, Solidity, Fit Ellipse (for aspect ratio), Mean gray value

---

## Required Measurements Per Nucleus

| Column | Description |
|--------|-------------|
| image_filename | Source image filename |
| nucleus_id | Sequential ID within image |
| area_px | Area in pixels |
| perimeter_px | Perimeter in pixels |
| circularity | 4π×Area/Perimeter² (0=elongated, 1=perfect circle) |
| solidity | Area / Convex Hull Area |
| aspect_ratio | Major axis / Minor axis from ellipse fit |
| mean_intensity | Mean pixel intensity in original image |
| area_um2 | Area converted to µm² (area_px × 0.3296²) |
| perimeter_um | Perimeter converted to µm (perimeter_px × 0.3296) |

---

## Required Output Files

### 1. Nuclear Measurements CSV
**Path**: `~/Fiji_Data/results/morphometry/nuclear_measurements.csv`
**Format**: CSV with header row, one row per detected nucleus
**Content**: All columns listed above for all nuclei across all DAPI images

### 2. Batch Summary
**Path**: `~/Fiji_Data/results/morphometry/batch_summary.txt`
**Format**: Text file, one line per image
**Content per line**: filename, n_nuclei, mean_area_um2, mean_circularity, QC_flag
**QC flag rules**:
- `PASS`: n_nuclei >= 5 AND mean_circularity >= 0.5
- `FAIL`: n_nuclei < 5 OR mean_circularity < 0.5

Example batch_summary.txt:
```
filename,n_nuclei,mean_area_um2,mean_circularity,qc_flag
BBBC008_v1_A01_s1_w1.TIF,18,52.3,0.73,PASS
BBBC008_v1_A01_s2_w1.TIF,14,49.8,0.71,PASS
BBBC008_v1_A02_s1_w1.TIF,3,61.2,0.68,FAIL
```

### 3. QC Overlay Image
**Path**: `~/Fiji_Data/results/morphometry/qc_overlay.png`
**Format**: PNG image (> 5 KB)
**Content**: One processed image with detected nucleus outlines drawn on it, demonstrating the segmentation quality

---

## Fiji Macro Approach (Recommended)

You can automate the full batch pipeline using a Fiji macro. Example skeleton:

```javascript
// Fiji macro for batch nuclear morphometry
inputDir = "/home/ga/Fiji_Data/raw/bbbc008/";
outputDir = "/home/ga/Fiji_Data/results/morphometry/";
scale = 0.3296; // um/pixel

// Set measurements
run("Set Measurements...", "area perimeter shape fit mean redirect=None decimal=3");

// Process each w1 (DAPI) file
list = getFileList(inputDir);
for (i = 0; i < list.length; i++) {
    if (indexOf(list[i], "w1") >= 0) {
        open(inputDir + list[i]);
        // Background subtraction
        run("Subtract Background...", "rolling=50");
        // ... threshold, watershed, analyze particles ...
        close("*");
    }
}
```

Use `Plugins > Macros > New...` or `Plugins > Macros > Run...` to execute.

---

## Verification Criteria

The task verifier checks:

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV created after task start | 15 | File mtime > task start timestamp |
| Required morphometry columns | 15 | Must include area, circularity, solidity columns |
| >= 50 total nuclei measured | 20 | Batch processing of multiple images (10 pts for >= 20) |
| Valid circularity and solidity values | 15 | All values in range (0, 1] |
| Positive area values | 10 | All area_px > 0 |
| Batch summary with QC flags | 15 | Contains PASS/FAIL flags (10 pts if exists without flags) |
| QC overlay image | 10 | PNG file > 5 KB |
| **Total** | **100** | **Pass threshold: 60** |

---

## Tips

- Use `Analyze > Set Scale...` to set the pixel scale before running Analyze Particles so measurements are automatically in µm
- The Results table in Fiji can be saved directly as CSV via `File > Save As...` in the Results window
- For batch processing, a macro that loops over all files is most efficient
- Use `IJ.log()` in macros to debug or track progress
- Save the Results table after each image and append to a master CSV, or use a macro that accumulates all measurements before saving
