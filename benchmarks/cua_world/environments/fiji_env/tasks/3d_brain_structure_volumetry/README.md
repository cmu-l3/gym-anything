# Task: 3d_brain_structure_volumetry

## Overview

**Role**: Medical Scientist / Nanotechnology Technician
**Difficulty**: Very Hard
**Timeout**: 900 seconds (15 minutes), 80 max steps

You are a medical scientist performing quantitative 3D volumetric analysis of a human brain MRI scan. Using Fiji's 3D image processing capabilities, you will segment and measure two anatomically distinct brain structures from a 27-slice MRI stack, producing clinically-relevant volumetric measurements.

---

## Dataset: ImageJ MRI Stack

**Source**: ImageJ/Fiji built-in sample data (public domain)
**URL**: https://imagej.nih.gov/ij/images/mri-stack.zip
**Modality**: T1-weighted axial MRI, human brain
**Location**: `~/Fiji_Data/raw/mri/mri_stack.tif`

**Stack properties**:
- Dimensions: 186 × 226 pixels × 27 slices
- Bit depth: 16-bit grayscale
- Format: Multi-page TIFF (image stack)

**Voxel dimensions** (documented in `~/Fiji_Data/raw/mri/voxel_info.txt`):
- Width: 1.0 mm/pixel
- Height: 1.0 mm/pixel
- Depth (slice thickness): 1.5 mm/slice
- Voxel volume: 1.0 × 1.0 × 1.5 = 1.5 mm³

---

## Structures to Segment

### 1. Brain Tissue (Bright Region)
T1-weighted MRI images show brain tissue as bright signal, with darker surrounding structures (skull, fat) and a very dark background.

**Segmentation approach**:
- Apply threshold to isolate bright tissue (signal > ~1500 in 16-bit range)
- Use `Plugins > 3D > 3D Objects Counter` or `Analyze > Analyze Particles` on each slice
- Identify and keep the largest connected component (main brain mass)
- Exclude skull by working on interior tissue region

**Expected brain volume**: Roughly 500,000 - 2,000,000 mm³ for the cropped stack
(Note: the 27-slice stack captures a partial brain volume, not the entire brain)

### 2. Ventricles (Dark Hypo-intense Regions)
The cerebral ventricles (lateral ventricles, third ventricle) appear dark in T1-weighted MRI because they are filled with cerebrospinal fluid (CSF), which has low T1 signal intensity.

**Segmentation approach**:
- Within the brain tissue mask, identify dark regions (low intensity)
- Apply inverse threshold within the brain mask region
- CSF/ventricle signal is typically in the range ~200-800 (16-bit values)
- Use connected component analysis to identify ventricle structures

**Expected ventricle volume**: Typically < 5% of brain volume in healthy adults

---

## Analysis Pipeline

### Step 1: Load the Stack
`File > Open... → ~/Fiji_Data/raw/mri/mri_stack.tif`

### Step 2: Set Voxel Dimensions
`Image > Properties...`
Set:
- Pixel Width: 1.0 mm
- Pixel Height: 1.0 mm
- Voxel Depth: 1.5 mm
- Unit: mm

### Step 3: Segment Brain Tissue
```
// Duplicate for thresholding
run("Duplicate...", "title=brain_mask duplicate");
// Set threshold for bright tissue
setThreshold(1500, 65535);
run("Convert to Mask", "stack");
// Apply watershed or morphological closing to clean up
run("Fill Holes", "stack");
// 3D connected components to find largest object
run("3D Objects Counter", "threshold=1 slice=14 min=10000 max=99999999 objects statistics summary");
```

### Step 4: Segment Ventricles
```
// Create ventricle mask: dark regions within brain
selectWindow("mri_stack.tif");
run("Duplicate...", "title=ventricle_mask duplicate");
setThreshold(0, 800);  // Low intensity = CSF
run("Convert to Mask", "stack");
// Intersect with brain mask to exclude background
imageCalculator("AND stack", "ventricle_mask", "brain_mask");
```

### Step 5: Measure Volumes
For each binary mask:
- **Volume in voxels**: count of white pixels summed across all slices
- **Volume in mm³**: voxel_count × 1.0 × 1.0 × 1.5

Using `Analyze > Set Measurements...` and `Analyze Particles` or `3D Objects Counter`.

### Step 6: Create Orthogonal Views
`Image > Stacks > Orthogonal Views` or:
```
run("Orthogonal Views");
```
Save the resulting composite as orthogonal_views.tif.

---

## Required Output Files

### 1. Volume Measurements CSV
**Path**: `~/Fiji_Data/results/volumetry/volume_measurements.csv`
**Format**: CSV with header row

| Column | Description |
|--------|-------------|
| structure_name | "brain_tissue" or "ventricles" |
| volume_voxels | Volume in voxel count |
| volume_mm3 | Volume in cubic millimeters |
| surface_area_mm2 | Surface area in mm² (optional, can be 0 if unavailable) |
| sphericity | Sphericity metric 0-1 (optional, can be 0 if unavailable) |

Example:
```csv
structure_name,volume_voxels,volume_mm3,surface_area_mm2,sphericity
brain_tissue,856432,1284648.0,28340.5,0.42
ventricles,12840,19260.0,3210.0,0.31
```

### 2. Orthogonal Views
**Path**: `~/Fiji_Data/results/volumetry/orthogonal_views.tif`
**Format**: TIFF image (> 10 KB)
**Content**: XY, XZ, and YZ cross-sectional views of the MRI stack, typically shown as a composite

### 3. Volumetry Report
**Path**: `~/Fiji_Data/results/volumetry/volumetry_report.txt`
**Format**: Text file
**Required content**:
- Brain tissue volume measurement (mm³)
- Ventricle volume measurement (mm³)
- Ventricle-to-brain ratio (%)
- Statement about whether ventricle volume < 5% of brain volume

Example:
```
=== Brain Volumetry Report ===
MRI Stack: mri_stack.tif (27 slices, 1.0 x 1.0 x 1.5 mm voxels)

Structure 1: Brain Tissue
  Volume: 1,284,648 mm3
  Voxel count: 856,432

Structure 2: Ventricles (CSF spaces)
  Volume: 19,260 mm3
  Voxel count: 12,840

Ventricle/Brain ratio: 1.50%
Assessment: Ventricle volume < 5% of brain volume - NORMAL
```

---

## Verification Criteria

| Criterion | Points | Requirement |
|-----------|--------|-------------|
| CSV created after task start | 15 | File mtime > task start timestamp |
| Required volume columns present | 15 | structure_name, volume_voxels, volume_mm3 |
| >= 2 structures measured | 15 | Both brain tissue and ventricles |
| All volume_mm3 > 0 | 15 | No zero or negative volumes |
| Brain volume plausible | 15 | > 100 mm³, < 10^7 mm³ |
| Orthogonal views image | 15 | TIF file > 10 KB |
| Report with relevant keywords | 10 | Contains 'brain', 'ventricle', 'volume' |
| **Total** | **100** | **Pass threshold: 60** |

---

## Fiji 3D Tools Available

- `Plugins > 3D > 3D Objects Counter` - counts connected 3D objects, measures volumes
- `Analyze > Analyze Particles...` - 2D particle analysis (apply to each slice, sum volumes)
- `Image > Stacks > Orthogonal Views` - creates orthogonal cross-sections
- `Plugins > MorphoLibJ > Morphological Filters 3D` - advanced 3D morphology
- `Plugins > BoneJ > Isosurface` - surface rendering and measurements

## Tips

- Use `Image > Properties...` to set voxel dimensions before measuring so results are in mm³
- The `3D Objects Counter` plugin directly reports object volumes in calibrated units
- For ventricles, consider using `Edit > Selection > Create Selection` from the brain mask and measuring within it
- Orthogonal views can be captured as a screenshot or saved via `File > Save As > Tiff...` on the composite
- Use `IJ.log()` in macros to print measurement values to the Log window before saving
