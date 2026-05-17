> **Note:** This file was generated against an earlier version of the gym-anything
> library. Some paths (e.g. `gym_anything/runners/...`, `examples/<env>/...`,
> `constants.py`) and APIs (e.g. `env.verify()`, `env._runner.ssh_port`) referenced
> below may have moved or been renamed. Cross-check against the current source tree
> (`src/gym_anything/...`, `benchmarks/cua_world/environments/...`,
> `env.get_session_info()`) before relying on any path or import here.

# Slicer3D Easy Task Implementation Plan

Based on trajectory analysis, this document outlines specific tasks designed to be achievable by current models while still providing training signal.

## Summary of Key Insight

The model's primary failure mode is **endless scrolling** looking for the "perfect" anatomical level. Tasks succeed when:
1. Relevant structures are already visible
2. No anatomical level searching required
3. Visual landmarks are obvious
4. Model can take decisive action without uncertainty

## Tier 1: UI Operations (Target: >70% success)

These tasks test basic Slicer UI operations that the model reliably performs.

### Task 1.1: load_and_verify_data

**Description**: Load sample brain MRI and verify it displays correctly.

**Why achievable**:
- cardiothoracic_ratio trajectory showed model CAN navigate file dialogs
- No anatomical knowledge required
- Clear success criteria (data visible)

**Setup script should**:
- Launch Slicer without data loaded
- Ensure sample file exists at known location

**Task instruction**:
```
Load the brain MRI file from ~/Documents/SlicerData/SampleData/MRHead.nrrd
into 3D Slicer using File > Add Data. Verify the brain scan appears in
the slice views.
```

**Verifier criteria**:
- MRHead volume loaded (API check)
- Brain visible in at least one slice view (VLM check)

**Already exists**: Yes (load_sample_data) - can use as baseline

---

### Task 1.2: switch_to_markups_module

**Description**: Navigate from Welcome screen to Markups module.

**Why achievable**:
- Every trajectory shows model successfully switches modules
- Direct menu navigation, no ambiguity

**Setup script should**:
- Launch Slicer (starts in Welcome)
- Pre-load sample data so something is visible

**Task instruction**:
```
The Slicer window currently shows the Welcome screen. Navigate to the
Markups module using the Modules dropdown menu. Verify you can see the
Markups creation tools (Point List, Line, Angle, etc.).
```

**Verifier criteria**:
- Current module is "Markups" (API check)
- Markup tools visible in left panel (VLM check)

---

### Task 1.3: save_screenshot_to_file

**Description**: Capture and save a screenshot.

**Why achievable**:
- File saving works (tumor_ventricle_proximity)
- No measurement required
- Clear visual output

**Setup script should**:
- Launch Slicer with MRHead loaded
- Create output directory

**Task instruction**:
```
A brain MRI is loaded in 3D Slicer. Use the Screen Capture tool
(or keyboard shortcut) to save a screenshot of the current view
to ~/Documents/SlicerData/Screenshots/brain_view.png
```

**Verifier criteria**:
- Screenshot file exists
- File size > 10KB
- VLM confirms it shows brain scan

---

### Task 1.4: change_window_level_preset

**Description**: Change window/level to a specific preset.

**Why achievable**:
- window_level_optimization trajectory showed model CAN adjust W/L
- Dropdown selection is reliable
- No measurement required

**Setup script should**:
- Launch Slicer with CT data loaded
- Start with default W/L settings

**Task instruction**:
```
A chest CT scan is loaded in 3D Slicer. Go to the Volumes module and
change the Window/Level preset to "CT-Bone" to optimize visualization
of bone structures. The preset is available in the Window Level dropdown.
```

**Verifier criteria**:
- W/L preset is "CT-Bone" (API check)
- Bone structures now visible/bright (VLM check)

---

## Tier 2: Pre-Positioned Measurements (Target: >40% success)

These tasks test measurement placement WITHOUT requiring anatomical level searching.

### Task 2.1: measure_visible_circle

**Description**: Measure diameter of an obvious circular structure.

**Why achievable**:
- Model CAN place Line measurements (tumor_ventricle_proximity)
- No scrolling needed - structure is centered and visible
- Wide tolerance for measurement accuracy

**Setup script should**:
- Load CT data
- Navigate to slice showing clear circular aorta cross-section
- Center the view on the structure
- Save ground truth diameter

**Task instruction**:
```
A CT scan slice is displayed showing a large circular blood vessel
(the aorta) in the center of the view. Use the Markups > Line tool
to measure the diameter of this circular structure. The vessel appears
as a bright circle in the center of the image.

Save the measurement markup to ~/Documents/SlicerData/output/vessel_diameter.mrk.json
```

**Verifier criteria**:
- Line measurement exists
- Measurement is within ±20mm of ground truth (generous tolerance)
- Both points are near the vessel boundaries (within 30 pixels)

**Key innovation**: Pre-position to correct slice, so model doesn't scroll!

---

### Task 2.2: place_fiducial_at_center

**Description**: Place a fiducial point at the visible structure's center.

**Why achievable**:
- Point placement is simpler than line placement
- No ambiguity about location (visible center)
- Single click action

**Setup script should**:
- Load brain MRI
- Navigate to slice showing clear tumor
- Ensure tumor is obviously visible (hyperintense)

**Task instruction**:
```
A brain MRI slice is displayed showing a bright lesion (tumor).
Use the Markups > Point tool to place a single fiducial point
at the approximate center of the bright lesion.

Save the markup to ~/Documents/SlicerData/output/tumor_center.mrk.json
```

**Verifier criteria**:
- Point fiducial exists
- Point is within the tumor boundaries (based on segmentation)

---

### Task 2.3: measure_between_existing_points

**Description**: Create a Line measurement between two pre-existing fiducials.

**Why achievable**:
- Points already exist - model just connects them
- No need to find anatomical landmarks
- Tests Line tool usage without uncertainty

**Setup script should**:
- Load data with two pre-placed fiducial points (Point_A, Point_B)
- Points visible in the slice view

**Task instruction**:
```
Two fiducial points labeled "Point_A" and "Point_B" are already placed
in the scene. Use the Markups > Line tool to measure the distance
between these two points by clicking on each point in sequence.

The measurement should appear as a line connecting the two existing points.
Save to ~/Documents/SlicerData/output/distance_measurement.mrk.json
```

**Verifier criteria**:
- Line measurement exists
- Line endpoints are at the fiducial locations (within tolerance)
- Measured distance matches expected value

---

## Tier 3: Guided Measurements (Target: >20% success)

These tasks require some interpretation but minimize anatomical ambiguity.

### Task 3.1: measure_bright_tumor_diameter

**Description**: Measure the maximum diameter of an obviously visible tumor.

**Why achievable**:
- Tumor is highly visible (hyperintense on FLAIR/T1ce)
- No need to find "correct slice" - tumor already visible
- Similar to tumor_ventricle_proximity which scored 31 points

**Setup script should**:
- Load brain MRI (BraTS data)
- Navigate to slice with maximum tumor cross-section
- Ensure tumor is centered and obvious

**Task instruction**:
```
A brain MRI slice is displayed showing a glioma tumor. The tumor
appears as a bright region on this FLAIR image. Use the Markups > Line
tool to measure the maximum diameter of the bright tumor region.

Place one point at one edge of the tumor and the second point at
the opposite edge, measuring across the widest part.

Save to ~/Documents/SlicerData/BraTS/tumor_diameter.mrk.json
```

**Verifier criteria**:
- Line measurement exists
- Both endpoints are within/near tumor boundaries
- Diameter within ±15mm of ground truth

---

### Task 3.2: annotate_visible_structure

**Description**: Create a text annotation naming the central structure.

**Why achievable**:
- Uses text input (model can type)
- Structure is obvious (heart in chest CT)
- No measurement accuracy required

**Setup script should**:
- Load chest CT
- Navigate to slice showing heart clearly
- Heart is centered in view

**Task instruction**:
```
A chest CT slice is displayed showing the heart in the center.
Create a text annotation labeling this central structure as "Heart".

Use Markups > Create new annotation or right-click to add text.
Place the label near the center of the image where the heart is visible.
```

**Verifier criteria**:
- Text annotation exists
- Contains "heart" (case-insensitive)
- Located near center of image

---

### Task 3.3: count_visible_nodules

**Description**: Place fiducials on visible lung nodules.

**Why achievable**:
- Nodules are pre-highlighted or obviously visible
- Counting is simpler than precise measurement
- Multiple correct answers possible

**Setup script should**:
- Load chest CT with 3 visible nodules
- Navigate to slice showing all nodules
- Nodules are > 10mm for easy visibility

**Task instruction**:
```
A chest CT slice is displayed showing the lungs. There are 3 nodules
(round bright spots) visible in this image. Place a fiducial point
on each nodule using the Markups > Point tool.

Save the markup list to ~/Documents/SlicerData/output/nodule_markers.mrk.json
```

**Verifier criteria**:
- At least 2 fiducials placed (partial credit)
- 3 fiducials for full credit
- Each fiducial is within 20 pixels of a nodule center

---

## Tier 4: Minimal Navigation (Target: >10% success)

These tasks require 1-2 slice scrolls maximum.

### Task 4.1: scroll_one_slice_measure

**Description**: Scroll one slice to center structure, then measure.

**Why achievable**:
- Only 1-2 scroll actions needed
- Structure visible but slightly off-center
- Tests minimal navigation + measurement

**Setup script should**:
- Load data
- Position 1-2 slices away from optimal view
- Provide hint about direction

**Task instruction**:
```
A CT scan is loaded showing the abdomen. The aorta is visible but
slightly off-center in the current slice. Scroll UP 1-2 slices to
center the aorta in the view, then measure its diameter using
the Markups > Line tool.

The aorta is the circular structure just to the left of the spine.
Save to ~/Documents/SlicerData/output/aorta_diameter.mrk.json
```

**Verifier criteria**:
- Line measurement exists
- Model scrolled (slice changed from initial)
- Measurement reasonably close to aorta

---

## Implementation Priority

### Phase 1: Baseline (Week 1)
1. Verify load_sample_data task works
2. Create switch_to_markups_module
3. Create save_screenshot_to_file

### Phase 2: Easy Measurements (Week 2)
4. Create measure_visible_circle (Tier 2 flagship task)
5. Create place_fiducial_at_center
6. Create measure_between_existing_points

### Phase 3: Guided Tasks (Week 3)
7. Create measure_bright_tumor_diameter
8. Create count_visible_nodules

### Phase 4: Minimal Navigation (Week 4)
9. Create scroll_one_slice_measure
10. Iterate based on model performance

## Setup Script Template

```bash
#!/bin/bash
# Template for pre-positioned task setup

source /workspace/scripts/task_utils.sh

# 1. Load data
launch_slicer_with_file "/path/to/data.nrrd" ga

# 2. Wait for Slicer to fully load
sleep 5

# 3. Navigate to correct slice using Slicer's Python interface
python3 << 'EOF'
import slicer
# Get the red (axial) slice logic
red = slicer.app.layoutManager().sliceWidget("Red").sliceLogic()
# Set to specific slice position (no scrolling needed by agent)
red.SetSliceOffset(100.0)  # Adjust to correct anatomical level
EOF

# 4. Navigate to correct module
python3 << 'EOF'
import slicer
slicer.util.selectModule("Markups")
EOF

# 5. Focus and maximize window
WID=$(get_slicer_window_id)
focus_window "$WID"

# 6. Record ground truth
echo '{"gt_diameter_mm": 25.0, "slice_position": 100.0}' > /tmp/ground_truth.json

echo "=== Task ready: Structure is visible, just measure it ==="
```

## Verifier Design Principles

1. **Wide tolerance**: Accept measurements within ±20-30% of ground truth
2. **Partial credit**: Give points for any reasonable attempt
3. **Multiple criteria**: Score each step independently
4. **VLM backup**: Use VLM to verify visual correctness when API checks fail

## Expected Success Rates

| Tier | Current Rate | Target Rate | Training Value |
|------|-------------|-------------|----------------|
| Tier 1 (UI) | ~0% | >70% | Basic operations |
| Tier 2 (Pre-positioned) | ~0% | >40% | Measurement placement |
| Tier 3 (Guided) | ~1% | >20% | Interpretation + action |
| Tier 4 (Minimal nav) | ~0% | >10% | Limited navigation |
| Tier 5 (Current hard) | <2% | <5% | Complex reasoning |

## Next Steps

1. Implement Task 2.1 (measure_visible_circle) as proof of concept
2. Test with model to validate hypothesis
3. Iterate on setup script to minimize scrolling behavior
4. Create task suite for model training curriculum
