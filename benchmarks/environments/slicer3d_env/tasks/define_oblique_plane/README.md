# Define Oblique Plane Through Landmarks (`define_oblique_plane@1`)

## Overview

This task tests the agent's ability to create a plane markup by placing control points at specific anatomical landmarks - a fundamental skill for defining custom imaging planes, surgical approaches, and standardized neuroimaging orientations like the AC-PC plane.

## Rationale

**Why this task is valuable:**
- Tests plane markup creation in the Markups module
- Requires precise anatomical landmark identification
- Combines multiple fiducial placements into a geometric construct
- Essential for surgical planning and standardized image reformatting
- Different from simple point placement - requires understanding 3D geometry

**Real-world Context:** A neurosurgeon is preparing for a deep brain stimulation (DBS) procedure. They need to establish the AC-PC plane (anterior commissure - posterior commissure line) as the reference for targeting the subthalamic nucleus. This standardized plane must be defined by marking the AC, PC, and a superior midline point to create a properly oriented reference coordinate system.

## Task Description

**Goal:** Create a plane markup in 3D Slicer defined by three neuroanatomical landmarks:
1. Anterior Commissure (AC)
2. Posterior Commissure (PC)
3. A superior midline point on the interhemispheric fissure

**Starting State:** 3D Slicer is open with the brain MRI sample data loaded (MRHead.nrrd). The axial, sagittal, and coronal views are visible. No markups exist in the scene.

**Expected Actions:**
1. Navigate to the Markups module (via Modules menu or search)
2. Create a new Plane markup (Markups toolbar → Create Plane, or right-click in Markups module)
3. Navigate in the slice views to locate the anterior commissure (small white matter bundle anterior to the third ventricle on midline sagittal view)
4. Place the first control point at the center of the AC
5. Navigate to locate the posterior commissure (small structure at the posterior third ventricle, inferior to pineal gland)
6. Place the second control point at the center of the PC
7. Navigate to a point on the interhemispheric fissure superior to the AC-PC line (e.g., superior sagittal sinus or falx)
8. Place the third control point to define the plane orientation
9. Save the plane markup to ~/Documents/SlicerData/acpc_plane.mrk.json

**Final State:** A plane markup node exists with three control points at anatomically appropriate locations. The plane should be approximately axial (horizontal) in orientation, passing through the AC and PC.

## Verification Strategy

### Primary Verification: Markup Node Analysis

The verifier will query the exported results to:
1. Check that a Plane markup node exists
2. Extract the three control point RAS coordinates
3. Compare Point 1 (AC) to ground truth AC coordinates (tolerance: 5mm)
4. Compare Point 2 (PC) to ground truth PC coordinates (tolerance: 5mm)
5. Verify Point 3 is on or near the midline (|R| < 5mm) and superior to AC-PC line
6. Calculate plane normal vector and verify it's approximately superior (within 30° of [0,0,1])

### Secondary Verification: VLM Trajectory Check

- Examine trajectory screenshots to confirm navigation to appropriate brain regions
- Verify the Markups module was accessed
- Confirm control points are visible on midline structures

### Anti-Gaming Measures

1. **Timestamp Check:** Plane markup must be created after task start
2. **Control Point Geometry:** Points must form a valid plane (not collinear)
3. **Anatomical Plausibility:** Points must be within reasonable brain boundaries
4. **Process Verification:** Screenshots should show navigation to relevant slices

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| Plane Markup Exists | 15 | A plane markup node is present in the scene |
| Three Control Points | 15 | Plane has exactly 3 control points defined |
| AC Point Accurate | 20 | First point within 5mm of ground truth AC |
| PC Point Accurate | 20 | Second point within 5mm of ground truth PC |
| Superior Point Valid | 15 | Third point is on midline and superior to AC-PC |
| Plane Orientation Correct | 15 | Plane normal approximately superior-inferior |
| **Total** | **100** | |

**Pass Threshold:** 65 points with Plane Markup Exists criterion met

## Ground Truth Derivation

For MRHead sample data, the ground truth AC-PC coordinates are pre-computed:
- **AC Location:** Approximately R=0, A=1.5, S=-4 (in RAS coordinates)
- **PC Location:** Approximately R=0, A=-24.5, S=-2 (in RAS coordinates)
- **AC-PC Distance:** Approximately 26mm

## Data Source

**Dataset:** 3D Slicer Sample Data (MRHead)
- Standard T1-weighted brain MRI included with Slicer
- Publicly available, no license restrictions
- AC and PC landmarks identifiable in standard adult brain MRI
- Ground truth coordinates determined from anatomical standards

## Technical Notes

### Markup Plane Creation Methods
The agent can create a plane markup via:
1. Markups toolbar → down arrow → Plane
2. Markups module → Create → Plane
3. Keyboard shortcut if configured

### Anatomical Guidance
- **Anterior Commissure:** Best seen on midsagittal slice as a small white matter bundle crossing midline anterior to the fornix columns
- **Posterior Commissure:** Located at the junction of the aqueduct and third ventricle, below the pineal gland
- **Superior midline point:** Any point clearly on the interhemispheric fissure/falx cerebri, superior to AC-PC line

### Expected Challenges
- Requires precise slice navigation to visualize small structures
- Must understand 3D orientation of plane defined by 3 points
- Need to place points in correct order (some implementations are order-sensitive)