# Load Sample Data (`load_sample_data@1`)

## Overview

This is a simple introductory task that tests the agent's ability to load medical imaging data into 3D Slicer. It verifies basic file loading and UI interaction capabilities.

## Rationale

**Why this task is valuable:**
- Foundation skill for all 3D Slicer tasks
- Tests basic file dialog interaction
- Validates that the agent can verify successful data loading
- Quick feedback loop for agent development

**Real-world Context:** A researcher needs to open a brain MRI scan to examine its contents before analysis.

## Task Description

**Goal:** Load an MRI brain scan file and confirm it displays correctly in the slice views.

**Starting State:** 3D Slicer is open with an empty scene. The sample data file exists at `~/Documents/SlicerData/SampleData/MRHead.nrrd`.

**Expected Actions:**
1. Navigate to File > Add Data (or use keyboard shortcut Ctrl+O)
2. Browse to `~/Documents/SlicerData/SampleData/`
3. Select `MRHead.nrrd`
4. Click OK/Load to load the file
5. Verify the brain scan is visible in the slice views

**Final State:** The MRHead volume is loaded and visible in at least one slice view (axial, sagittal, or coronal).

## Verification Strategy

### Primary Verification: API State Check

The verifier queries 3D Slicer's internal state via Python API:
- Checks that a volume node exists in the MRML scene
- Verifies the loaded file matches the expected sample data
- Confirms data dimensions are correct

### Secondary Verification: VLM Visual Check

- Examines final screenshot for visible brain MRI data
- Verifies slice views show actual image content (not empty)

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Volume Node Exists | 40 | A volume was loaded into Slicer |
| Correct File Loaded | 30 | The loaded file is MRHead.nrrd |
| Data Visible | 20 | VLM confirms brain scan visible |
| Slice Views Active | 10 | At least one slice view shows data |
| **Total** | **100** | |

**Pass Threshold:** 70 points with Volume Node Exists

## Data Source

**Dataset:** 3D Slicer Sample Data
- Built-in sample data from 3D Slicer
- MRHead is a standard T1-weighted brain MRI
- Publicly available, no license restrictions
