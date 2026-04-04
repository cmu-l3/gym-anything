# Capture 3D Volume Rendering (`capture_3d_view@1`)

## Overview

This task tests the agent's ability to enable 3D volume rendering in 3D Slicer and capture a screenshot of the result. It combines data loading, visualization configuration, and screenshot capture.

## Rationale

**Why this task is valuable:**
- Tests navigation through Slicer's module system
- Requires understanding of volume rendering concepts
- Involves capturing visual evidence of work
- Common workflow for medical visualization

**Real-world Context:** A radiologist wants to create a 3D visualization of a brain scan to share with a surgical team.

## Task Description

**Goal:** Load MRI data, enable 3D volume rendering, and capture a screenshot of the volumetric brain visualization.

**Starting State:** 3D Slicer is open with an empty scene. Sample data is available at `~/Documents/SlicerData/SampleData/MRHead.nrrd`.

**Expected Actions:**
1. Load `MRHead.nrrd` from the sample data folder
2. Navigate to the Volume Rendering module (Modules menu or search)
3. Select the loaded volume in the module
4. Enable volume rendering by clicking the visibility (eye) icon
5. Adjust the 3D view camera to show the brain clearly
6. Optionally adjust the rendering preset for better visualization
7. Capture a screenshot using File > Save Scene and Data, or the Screen Capture module

**Final State:** A screenshot exists showing a 3D volume rendering of the brain.

## Verification Strategy

### Primary Verification: File-based + VLM Hybrid

1. **Screenshot Existence**: Verifies a screenshot file was created
2. **File Size Check**: Screenshot must be substantial (>100KB to ensure real content)
3. **VLM Analysis**: Examines screenshot for 3D volume rendering characteristics:
   - Is there a 3D volumetric brain visible?
   - Does it show depth/shading (not just 2D slices)?

### Secondary Verification: API State Check

- Confirms Volume Rendering module was accessed
- Checks that a volume rendering display node exists

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Screenshot Created | 25 | A screenshot file exists |
| Screenshot Size | 15 | File > 100KB (not empty/corrupt) |
| Volume Loaded | 20 | MRHead data was loaded |
| VR Module Used | 15 | Volume Rendering module accessed |
| 3D Rendering Visible | 25 | VLM confirms 3D brain visible |
| **Total** | **100** | |

**Pass Threshold:** 60 points with Screenshot Created

## Data Source

**Dataset:** 3D Slicer Sample Data
- MRHead.nrrd - standard T1-weighted brain MRI
- Built-in to 3D Slicer, no external download required
