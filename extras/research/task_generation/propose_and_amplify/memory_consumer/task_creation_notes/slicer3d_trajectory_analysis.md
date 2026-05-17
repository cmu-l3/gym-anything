> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Slicer3D Model Trajectory Analysis

## Executive Summary

Analysis of 34 model trajectories on Slicer3D tasks revealed a clear pattern: **all tasks failed** (0% pass rate), with only 2 tasks scoring any points:
- **tumor_ventricle_proximity**: 31/100 points (best performer)
- **ivc_diameter_assessment**: 5/100 points
- **All other 32 tasks**: 0 points

The primary failure mode is the **"scrolling loop"** - the model gets stuck endlessly scrolling through image slices looking for the "perfect" anatomical level, never committing to actually placing measurements.

## Detailed Failure Analysis

### Failure Pattern: The Scrolling Loop

**Observed in**: aorta_measurement, ivc_diameter_assessment, cardiothoracic_ratio, and likely most 0-score tasks.

**Behavior:**
1. Model correctly identifies the task (e.g., "measure aorta diameter")
2. Model correctly navigates to Markups module and activates Line tool
3. Model begins scrolling to "find the correct anatomical level"
4. Model scrolls back and forth through entire image volume
5. **Never commits to placing a measurement**
6. All 20 steps consumed by scrolling

**Example from aorta_measurement (20 steps):**
```
Step 1: Click Welcome X button
Step 2: Open Modules dropdown
Step 3: Click Markups
Step 4: Click axial view to focus
Steps 5-20: Scroll, scroll, scroll... "Continue scrolling to find the maximum aortic diameter level"
Result: 0 points - No measurement placed
```

**Example from ivc_diameter_assessment (20 steps):**
```
Steps 1-3: Navigate to Markups module
Steps 4-20: Scroll from slice 123 → 0 → 123 looking for "intrahepatic IVC level"
Result: 5 points (morphology assessment only - no actual measurement)
```

### Success Pattern: Decisive Action

**Observed in**: tumor_ventricle_proximity (31 points)

**Key differences:**
1. Data was pre-loaded with tumor and ventricles visible
2. Model did NOT scroll extensively
3. Model immediately placed measurement on visible slice
4. Successfully navigated File > Save dialogs
5. Ran out of steps before completing report file, but core measurement was done

**Example from tumor_ventricle_proximity (20 steps):**
```
Step 1: Close Welcome panel
Step 2: Navigate to Modules dropdown
Step 3: Click Markups
Step 4: Click Line tool
Step 5: Click on tumor edge (first point)
Step 6: Click on ventricle wall (second point) - MEASUREMENT PLACED!
Steps 7-17: Navigate save dialogs, rename file, change directory, save
Steps 18-20: Try to open text editor for report
Result: 31 points - Measurement created, distance measured
```

## What the Model CAN Do

Based on trajectory analysis, the model successfully performs these operations:

### 1. UI Navigation
- Close panels (Welcome X button)
- Open dropdown menus (Modules dropdown)
- Navigate hierarchical menus
- Switch between modules

### 2. File Operations
- Navigate file browser dialogs
- Double-click to enter directories
- Select files/directories
- Click "Choose" and "OK" buttons
- Rename files in save dialogs
- Navigate to specific paths

### 3. Data Loading
- Add Data dialog
- Navigate to data directories
- Load DICOM data (with some errors)

### 4. Markup Placement (when decisive)
- Create Line measurements
- Place fiducial points
- See measurement values displayed

### 5. Module Switching
- Markups module
- Volume Rendering module
- Other modules via dropdown

## What the Model CANNOT Do (Currently)

### 1. Find Specific Anatomical Levels
The model lacks the domain knowledge to confidently identify:
- Maximum aortic diameter level
- Intrahepatic vs infrarenal IVC
- PA bifurcation level
- Vertebral levels (L2, L3, etc.)

### 2. Commit to Action Under Uncertainty
When unsure if a slice is "optimal", the model:
- Continues searching indefinitely
- Never makes a "good enough" decision
- Exhausts all steps without acting

### 3. Complex Multi-Step Medical Protocols
Tasks requiring:
- Multiple measurements at different levels
- Specific anatomical landmark identification
- Clinical interpretation/classification

## Design Principles for Easier Tasks

Based on this analysis, easier tasks should:

### Principle 1: Pre-Position the Data
- Load data to the correct slice BEFORE the task starts
- Ensure relevant structures are visible without scrolling
- Example: Instead of "find the L3 vertebra", start with L3 already displayed

### Principle 2: Make Landmarks Visually Obvious
- Use existing segmentations to highlight structures
- Use high-contrast modalities (bright tumor on FLAIR)
- Consider adding visual guides (arrows, circles) in setup

### Principle 3: Reduce Anatomical Ambiguity
- Don't require finding "maximum diameter" - just measure at visible level
- Don't require specific anatomical level identification
- Provide clear visual criteria ("measure the bright circular structure")

### Principle 4: Focus on UI Operations First
- Test loading data
- Test switching modules
- Test saving files
- Test taking screenshots
- These are reliably successful

### Principle 5: Break Complex Tasks into Steps
Instead of: "Measure aorta diameter at L2, classify, and report"
Use: "Measure the diameter of the visible vessel and save the markup"

### Principle 6: Allow "Good Enough" Measurements
- Wide tolerance thresholds
- Partial credit for attempt
- Don't require clinical precision

## Proposed Task Tiers

### Tier 1: Easy (UI Operations Only)

**Task 1.1: Load Sample Data and Verify**
- Load MRHead.nrrd from specified path
- Verify brain scan appears in slice views
- Success: Data visible in at least one view

**Task 1.2: Save Screenshot**
- Pre-load data
- Capture screenshot using Screen Capture tool
- Save to specified path
- Success: Screenshot file exists with non-zero size

**Task 1.3: Change Window/Level Preset**
- Pre-load CT scan
- Go to Volumes module
- Select a specific window/level preset (e.g., "CT-Bone")
- Success: Window/level values match preset

**Task 1.4: Switch Volume Rendering Preset**
- Pre-load data, enable volume rendering
- Change preset from default to specified preset (e.g., "MR-Default")
- Success: Preset selection verified

### Tier 2: Easy (Pre-Positioned Measurements)

**Task 2.1: Measure Pre-Highlighted Structure**
- Pre-load CT with aorta visible at center
- Pre-position to correct slice (no scrolling needed)
- Measure diameter of the obvious circular structure
- Wide tolerance (±10mm)
- Success: Any measurement placed on the structure

**Task 2.2: Place Fiducial at Visible Landmark**
- Pre-load brain MRI at midline slice
- Place point fiducial at the most anterior point of the brain
- Success: Fiducial placed in reasonable location

**Task 2.3: Measure Distance Between Marked Points**
- Pre-load image with two existing fiducial points
- Create Line measurement between them
- Success: Line measurement exists with any value

**Task 2.4: Identify Visible Structure**
- Pre-load CT showing heart
- Create text annotation naming the central structure
- Success: Annotation exists with reasonable text

### Tier 3: Medium (Guided Measurements)

**Task 3.1: Measure Visible Tumor**
- Pre-load brain MRI with tumor slice visible
- Tumor is obviously hyperintense
- Measure maximum diameter in any direction
- Generous tolerance (±15mm)
- Success: Measurement placed somewhere on bright region

**Task 3.2: Count Visible Structures**
- Pre-load chest CT showing multiple nodules
- Place fiducial on each visible nodule
- Success: At least 2 fiducials placed

**Task 3.3: Assess Window/Level Optimization**
- Pre-load CT with poor window settings
- Adjust W/L to make specific structure visible
- Success: W/L values in acceptable range

### Tier 4: Medium-Hard (Minimal Navigation Required)

**Task 4.1: Single Scroll Measurement**
- Pre-load data one slice away from target
- Model must scroll 1-2 slices only
- Place measurement on obvious structure
- Success: Measurement placed

**Task 4.2: Identify View Orientation**
- Pre-load data in all three views
- Create annotation identifying which view shows a specific structure best
- Success: Correct view identified

## Implementation Notes

### Setup Script Requirements
For easier tasks, setup scripts should:
1. Pre-load all necessary data
2. Navigate to the correct slice
3. Set appropriate window/level
4. Enable relevant modules
5. Position cursor near target structure

### Verifier Tolerance
For easier tasks, verifiers should:
1. Accept measurements within generous tolerance
2. Give partial credit for any attempt
3. Not require clinical precision
4. Focus on whether the model took correct actions

### Success Metrics
For model training purposes:
- Tier 1 tasks: Should achieve >70% success rate
- Tier 2 tasks: Should achieve >40% success rate
- Tier 3 tasks: Should achieve >20% success rate
- Tier 4 tasks: Should achieve >10% success rate

Current hard tasks (Tier 5): <2% success rate

## Appendix: Task Score Distribution

| Score | Count | Tasks |
|-------|-------|-------|
| 31 | 1 | tumor_ventricle_proximity |
| 5 | 1 | ivc_diameter_assessment |
| 0 | 32 | All others |

## Appendix: Successful Action Patterns

From tumor_ventricle_proximity (31 points):
1. Welcome panel → close (click X)
2. Modules dropdown → open (click dropdown)
3. Markups → select (click option)
4. Line tool → activate (click button)
5. First point → place (click on image)
6. Second point → place (click on image)
7. File menu → open (click File)
8. Save Data → select (click option)
9. Filename → edit (triple-click, type)
10. Directory → change (navigate dialogs)
11. Save → execute (click Save)

This sequence took 17 steps and successfully created and saved a measurement.
