# Simplify and Export PVsyst Shading Scene (`simplify_pvsyst_scene_export@1`)

## Overview
This task evaluates the agent's ability to optimize a complex, heavily detailed SketchUp model for export to PVsyst, the industry standard for solar energy modeling. The agent must remove high-polygon "entourage" components that cause PVsyst to crash, replace shading obstacles with low-poly mathematical proxies, purge the file memory, and export it to the universal COLLADA (.dae) format.

## Rationale
**Why this task is valuable:**
- Tests 3D model optimization and polygon management (a critical pre-simulation engineering workflow)
- Requires component identification, targeted deletion, and file purging
- Tests spatial reasoning by replacing a complex object with a volumetric proxy of similar dimensions
- Evaluates the ability to navigate standard 3D export workflows (.dae format)
- Addresses a ubiquitous real-world pain point where cross-departmental files must be "cleaned" before engineering analysis.

**Real-world Context:** 
A Solar Energy Systems Engineer receives a commercial solar proposal model from the sales department. To impress the client, the sales team added a highly detailed 3D oak tree and several 3D delivery vans to the model. The engineer now needs to import this scene into PVsyst to generate a bankable energy yield report. However, PVsyst will freeze and crash if it attempts to ingest those high-poly assets. The engineer must strip out the cars (which don't affect roof shadows), replace the detailed tree with a simple 40-foot rectangular block to preserve its shadow profile, completely purge the bloated components from the file's memory, and export a clean .dae file.

## Task Description

**Goal:** Remove the high-poly tree and vehicle from the model, replace the tree with a 40-foot-tall low-poly proxy block, purge unused components to reduce file size, and export the optimized scene as a COLLADA file.

**Starting State:** 
- SketchUp Make 2017 is running and maximized.
- The bloated model `C:\Users\Docker\Documents\client_proposal_bloated.skp` is open.
- The scene contains:
  - A commercial building with a flat roof.
  - A highly detailed tree component named `Detailed_Oak_Tree` located to the south-west.
  - A highly detailed vehicle component named `Detailed_Delivery_Van` in the parking lot.

**Expected Actions:**
1. Locate the `Detailed_Oak_Tree` component casting a shadow toward the building.
2. Note its approximate ground location, then delete the `Detailed_Oak_Tree` component.
3. Using the Rectangle and Push/Pull tools, create a simple rectangular box at the same ground location as the original tree.
4. Extrude the proxy box upward to a height of approximately **40 feet** (this acts as a low-poly shading obstacle).
5. Locate and delete the `Detailed_Delivery_Van` component from the parking lot.
6. Navigate to **Window > Model Info > Statistics** and click **Purge Unused** to permanently remove the deleted high-poly definitions from the file's memory database.
7. Save the optimized model to `C:\Users\Docker\Documents\optimized_shading_model.skp`.
8. Export the 3D scene via **File > Export > 3D Model**, selecting COLLADA File (`*.dae`), to `C:\Users\Docker\Documents\pvsyst_scene.dae`.

**Final State:**
- The high-poly tree and van are completely removed and purged.
- A tall rectangular proxy object exists where the tree used to be.
- The optimized `.skp` file is saved and significantly smaller than the original.
- The `.dae` file is successfully exported.

## Verification Strategy

### Primary Verification: File Metrics & String Parsing (File-based)
1. **File Existence:** Verify both `optimized_shading_model.skp` and `pvsyst_scene.dae` exist.
2. **File Size Optimization:** Compare the size of `optimized_shading_model.skp` against the original file. The new file must be smaller, verifying the "Purge Unused" action was actually performed.
3. **DAE Parsing (Anti-Gaming):** Read the `pvsyst_scene.dae` XML structure. The strings `"Detailed_Oak_Tree"` and `"Detailed_Delivery_Van"` MUST NOT exist in the file.

### Secondary Verification: VLM Trajectory Analysis
- Visual verification that the agent successfully drew and extruded a proxy box in place of the deleted tree component.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| DAE Exported | 15 | `pvsyst_scene.dae` exists and was created during task |
| SKP Saved | 10 | `optimized_shading_model.skp` exists and was created during task |
| Van Purged | 10 | `Detailed_Delivery_Van` is absent from the DAE file |
| Tree Purged | 15 | `Detailed_Oak_Tree` is absent from the DAE file |
| File Minimized | 20 | Final `.skp` file size is reduced by >40% from original |
| Proxy Box Created | 30 | VLM verifies a tall proxy box was created during the session |
| **Total** | **100** | |

**Pass Threshold:** 70 points, which MUST include successful DAE export and the deletion/purging of the tree component.