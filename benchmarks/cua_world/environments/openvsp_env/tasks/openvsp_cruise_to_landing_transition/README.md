# openvsp_cruise_to_landing_transition (`openvsp_cruise_to_landing_transition@1`)

## Overview
This task evaluates the agent's ability to transition a parametric aircraft model between distinct flight configurations (cruise to landing) by adding subsurfaces and modifying component spatial placement.

## Rationale
**Why this task is valuable:**
- Tests multi-component editing within a complex parametric model.
- Requires navigating specialized sub-menus (the "Sub" tab for Subsurfaces).
- Requires spatial kinematics adjustment (XForm pitch adjustment).
- **Real-world relevance:** Aerodynamicists constantly fork clean "cruise" geometry into "high-lift" (takeoff/landing) configurations before running CFD or panel method sweeps.

**Real-world Context:** The conceptual design team needs to estimate the approach speed of the eCRM-001 research aircraft. The aerodynamics engineer must deploy the trailing edge flaps and trim the horizontal tail incidence to balance the aircraft before running the low-speed aerodynamic solver.

## Task Description

**Goal:** Reconfigure the eCRM-001 aircraft model from cruise to landing configuration by adding a 35° flap and setting the tail incidence to -3°.

**Starting State:** OpenVSP is launched with the baseline `eCRM001_cruise.vsp3` model loaded. A checklist file `landing_config_checklist.txt` is available on the Desktop.

**Expected Actions:**
1. Select the Wing component.
2. Navigate to the "Sub" (Subsurface) tab and add a new subsurface.
3. Configure the subsurface as a "Flap" and set its Angle to 35.0 degrees.
4. Select the Horizontal Tail component.
5. Navigate to the "XForm" tab and change its Pitch (Y rotation) to -3.0 degrees.
6. Save the model as `/home/ga/Documents/OpenVSP/eCRM001_landing.vsp3`.

**Final State:** A new file `eCRM001_landing.vsp3` exists with the specified parameters permanently embedded in the XML structure.

## Verification Strategy

### Primary Verification: XML State Parsing
The verifier programmatically parses the saved OpenVSP `.vsp3` (which is XML) to confirm the exact parameter changes without relying solely on GUI state. It checks the Wing component for a Subsurface Flap at 35° and the Tail component for a Y-rotation of -3°.

### Secondary Verification: VLM Trajectory Check
To prevent anti-gaming (e.g., the agent just writing an XML file from scratch via script), a Vision-Language Model analyzes the trajectory frames to verify the agent actually interacted with the OpenVSP GUI panels (Sub tab, XForm tab).

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| File Saved | 15 | `eCRM001_landing.vsp3` exists |
| Modified During Task | 15 | File timestamp is after task start |
| Flap Added | 25 | Wing contains a Subsurface with Angle ≈ 35° |
| Tail Pitch Adjusted | 25 | Tail XForm Y_Rel_Rotation ≈ -3° |
| VLM Trajectory Valid | 20 | Trajectory shows GUI interaction with Sub/XForm tabs |
| **Total** | **100** | |

Pass Threshold: 70 points, requiring at least one valid parameter modification and a valid save.