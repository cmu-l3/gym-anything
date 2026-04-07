# 18650 Dual Battery Holder Enclosure (`18650_battery_holder@1`)

## Overview
This task tests the agent's ability to execute a fundamental plastics/enclosure design workflow in SolveSpace: creating a base solid, hollowing it out using a boolean difference (pocketing), and adding internal structural features (a separator rib). It requires precise dimensional control and an understanding of multi-group operations and combining modes.

## Rationale
**Why this task is valuable:**
- **Operation Sequencing:** Tests the critical CAD sequence of `Union (Base) -> Difference (Pocket/Hollow) -> Union (Internal Feature)`.
- **Workplane Selection:** Requires the agent to create new sketches on specifically generated faces (the top face for the pocket, and the internal floor for the rib).
- **Boolean Operations:** Evaluates the ability to configure mesh combining modes (setting an extrusion to subtract/cut instead of add).
- **Parametric Consistency:** Tests centering and symmetric constraints across multiple sketches.

**Real-world Context:** A product designer or electronics maker needs to 3D print a custom battery holder for a project powered by two standard 18650 lithium-ion cells. The dimensions are directly derived from the physical specifications of 18650 cells (18mm diameter, 65mm length), requiring a specific pocket size and a separating rib to prevent the cells from rubbing against each other.

## Task Description

**Goal:** Model a parametric dual 18650 battery holder with an internal pocket and a central separator rib, save the SolveSpace project, and export it as an STL.

**Starting State:** SolveSpace is open with a blank new sketch (default `sketch-in-plane` group on the XY workplane). 

**Expected Actions:**

1. **Base Block (Outer Shell):** 
   - In the initial sketch, draw a rectangle centered at the origin.
   - Constrain the dimensions to **44 mm wide (X)** and **71 mm high (Y)**.
   - Extrude this rectangle as a solid (Union) to a depth of **21 mm**.

2. **Pocket (Hollowing the Shell):**
   - Select the top face of the extruded base block and create a new sketch workplane on it.
   - Draw a rectangle centered at the origin.
   - Constrain the dimensions to **40 mm wide (X)** and **67 mm high (Y)**. (This establishes a 2mm outer wall thickness).
   - Extrude this rectangle into the block to a depth of **19 mm**. 
   - **Crucial:** Set this extrusion's mesh combining mode to **Difference** so it cuts a pocket into the base block, leaving a 2mm solid floor at the bottom.

3. **Separator Rib:**
   - Select the inside floor face of the newly created pocket and create a third sketch workplane on it.
   - Draw a rectangle running vertically down the center. 
   - Constrain its width to **2 mm (X)** and its height to **67 mm (Y)** (spanning the full interior length of the pocket).
   - Extrude this rectangle as a solid (Union) upward to a depth of **10 mm**.

4. **Save and Export:**
   - Save the project to `/home/ga/Documents/SolveSpace/18650_holder.slvs`.
   - Export the 3D triangle mesh to `/home/ga/Documents/SolveSpace/18650_holder.stl`.

**Final State:** 
- `/home/ga/Documents/SolveSpace/18650_holder.slvs` exists and contains three extrusion groups (Base, Pocket, and Rib).
- `/home/ga/Documents/SolveSpace/18650_holder.stl` exists and is a valid mesh representing the open-top battery tray.
- The 3D model in SolveSpace visually resembles a rectangular cup divided into two parallel bays.

## Verification Strategy

- **Primary Verification (File Structure):** Parses the `.slvs` text file natively in Python to verify the existence of 3 extrusions, ensure a Boolean Difference operation was recorded, and checks for the exact parameter dimension values.
- **Secondary Verification (STL output):** Confirms export process succeeded and the output file is of substantial size.
- **Tertiary Verification (VLM Visual Check):** A VLM inspects trajectory screenshots to confirm the 3D model visually matches a dual battery holder.