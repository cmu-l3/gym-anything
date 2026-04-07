# Configure Synthetic Data Generation for Semantic Segmentation (`configure_semantic_segmentation@1`)

## Overview
This task evaluates the agent's ability to configure a robotics simulation for synthetic dataset generation. The agent must modify a robot's vision sensors to enable object recognition and semantic segmentation, and assign specific class-label colors to objects in the environment.

## Rationale
**Why this task is valuable:**
- Tests the ability to instantiate complex nested nodes (adding a `Recognition` node inside a `Camera` node).
- Evaluates understanding of semantic segmentation concepts in the context of simulation.
- Exercises modification of base `Solid` properties (`recognitionColors`) across multiple environmental objects.
- **Real-world relevance**: Generating annotated synthetic data (bounding boxes and segmentation masks) is a primary use case for modern 3D simulators. Machine learning engineers rely on this to train computer vision models (like YOLO or Mask R-CNN) before deploying them on real robots.

**Real-world Context:** A computer vision engineer is building a dataset to train a warehouse sorting robot. The robot needs to identify and segment hazardous material barrels and shipping crates. The current Webots world has the 3D models and the robot, but the camera is only rendering standard RGB video. The engineer must configure the simulator to automatically output perfectly annotated segmentation masks by assigning standard class colors to the objects and enabling the camera's built-in recognition engine.

## Task Description

**Goal:** Configure the robot's camera to generate semantic segmentation masks and assign the correct class colors to the warehouse objects, then save the world.

**Starting State:** Webots is open with the world `warehouse_synthetic_gen.wbt` loaded. The scene contains:
- A `DEF WAREHOUSE_ROBOT Robot` with a `Camera` node named `"vision_sensor"`. The camera currently only outputs raw RGB video (its `recognition` field is empty).
- A `DEF HAZMAT_BARREL Solid` representing a chemical drum.
- A `DEF SHIPPING_CRATE Solid` representing a wooden box.

**Expected Actions:**
1. **Enable Camera Recognition:** Navigate to the `WAREHOUSE_ROBOT`'s `Camera` node ("vision_sensor") and add a `Recognition` node to its `recognition` field.
2. **Configure Recognition Engine:** Inside the newly added `Recognition` node:
   - Set `segmentation` to `TRUE` (enables the generation of a semantic mask image).
   - Set `maxRange` to **15.0** meters (matches the reliable depth range of the simulated RealSense D435i camera).
3. **Assign Semantic Class Colors:** To make objects show up in the segmentation mask, they must have a defined recognition color:
   - Navigate to the `DEF HAZMAT_BARREL` Solid and set its `recognitionColors` to **[1 0 0]** (Pure Red).
   - Navigate to the `DEF SHIPPING_CRATE` Solid and set its `recognitionColors` to **[0 0 1]** (Pure Blue).
4. **Save the World:** Save the fully configured world to **`/home/ga/Desktop/semantic_dataset_configured.wbt`**

**Final State:** A saved `.wbt` file exists on the Desktop. Inside the file, the camera contains a properly configured recognition engine, and both target objects have their semantic segmentation colors assigned.

## Verification Strategy

### Primary Verification: World File VRML Parsing
The verifier copies `/home/ga/Desktop/semantic_dataset_configured.wbt` from the VM and performs targeted text analysis on the VRML structure:

1. **File Check**: Verifies the file exists, has a minimum size, and was created during the task timeframe.
2. **Recognition Node Detection**: Parses the `Camera` block named `"vision_sensor"` to confirm the `recognition` field contains a `Recognition { ... }` node.
3. **Segmentation Parameters**: Extracts the `segmentation` and `maxRange` values from within the `Recognition` block.
4. **Semantic Colors Check**: Uses coordinate extraction to locate `DEF HAZMAT_BARREL Solid` and `DEF SHIPPING_CRATE Solid`, mathematically verifying the presence and accuracy of the `recognitionColors` array.

### Scoring System

| Criterion | Points | Description |
|-----------|--------|-------------|
| File Exists | 10 | World saved to the correct Desktop path |
| Created During Task | 10 | Output file modified/created after task start |
| Recognition Engine Added | 20 | `Camera` node has a valid `Recognition` child node |
| Segmentation Enabled | 20 | `Recognition` node has `segmentation TRUE` |
| Range Configured | 10 | `Recognition` node has `maxRange 15` |
| Hazmat Semantic Color | 15 | `HAZMAT_BARREL` has `recognitionColors [ 1 0 0 ]` |
| Crate Semantic Color | 15 | `SHIPPING_CRATE` has `recognitionColors [ 0 0 1 ]` |
| **Total** | **100** | |

**Pass Threshold:** 70 points (The agent must at least save the file, enable the recognition engine, and configure the colors for at least one object).