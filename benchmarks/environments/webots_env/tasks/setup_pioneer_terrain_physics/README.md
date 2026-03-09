# Task: Setup Pioneer 3-AT Terrain Physics

## Overview

**Difficulty**: Hard
**Occupation**: Field Robotics Engineer
**Industry**: Agricultural Robotics / Precision Agriculture / Mining
**Environment**: Webots 3D Robot Simulator

## Domain Context

Field robotics engineers use Webots to simulate robot behavior on unstructured outdoor terrain before physical deployment. Getting the physics parameters right is critical: a robot with wrong mass behaves unrealistically (tipping over too easily, or not toppling when it should), and missing contact properties mean wheel-terrain interaction uses generic defaults that don't match real friction characteristics.

The Pioneer 3-AT is a real, widely-used outdoor robot platform (manufactured by Omron Adept MobileRobots). Its actual mass of 12.5 kg and rubber-tire-on-gravel friction properties are well-documented. Using the wrong mass or friction values produces simulation data that cannot be used for controller tuning or failure prediction.

## Task Goal

Correct the physics configuration of a Pioneer 3-AT simulation world:

1. **Robot Physics Mass**: Set the Pioneer 3-AT robot body's `mass` to **12.5 kg** (currently wrong at 1.0 kg)
2. **ContactProperties**: Add a `ContactProperties` node to the WorldInfo defining wheel-terrain contact dynamics with `coulombFriction` of **0.7** and `softness` of **0.001** (for rubber wheel on packed gravel/agricultural dirt)

Save the corrected world to **`/home/ga/Desktop/pioneer_terrain.wbt`**

## Starting State

The world file `data/pioneer_field.wbt` is loaded in Webots with:
- `PIONEER_ROBOT` body Physics mass: 1.0 kg (wrong — real robot is 12.5 kg)
- No `ContactProperties` node exists in WorldInfo (missing terrain contact definition)
- Terrain is a flat dirt/gravel surface (Box geometry)

## Hardware Reference

**Pioneer 3-AT Robot Specifications** (Omron Adept MobileRobots):
- Total mass: 12.5 kg (without payload)
- Drive: 4-wheel differential drive
- Terrain: designed for outdoor packed terrain

**Contact Properties for Rubber Wheel on Compacted Gravel** (experimentally measured):
- Coulomb friction coefficient: 0.7
- Softness: 0.001 (stiffness of contact response)

## Success Criteria

The saved world at `/home/ga/Desktop/pioneer_terrain.wbt` must contain:
1. File exists at correct path — 10 points
2. Robot Physics mass between 10.0 and 15.0 kg (accepts ±2.5 tolerance around 12.5) — 30 points
3. A `ContactProperties` node is present in the world — 30 points
4. ContactProperties contains a friction value between 0.5 and 0.9 (includes 0.7 with tolerance) — 30 points

**Pass threshold**: 70/100 points

## Verification Strategy

The verifier:
1. Copies the saved `.wbt` file from the VM
2. Uses regex to find the `mass` value in the `PIONEER_ROBOT` Physics sub-node
3. Checks for presence of `ContactProperties` block in the file
4. Checks for `coulombFriction` value within acceptable range

## Features Exercised

| Feature | Description |
|---------|-------------|
| Scene tree navigation | Navigate robot node hierarchy to Physics sub-node |
| Physics node editing | Modify mass field in robot body physics |
| WorldInfo editing | Add ContactProperties node to world-level physics |
| ContactProperties configuration | Set friction and softness properties |
| File > Save World As | Save modified world to specific path |

## Edge Cases

- The agent must navigate to the correct PIONEER_ROBOT Physics node (not the wheel physics nodes)
- Adding ContactProperties requires finding the WorldInfo node's physics configuration section
- The `ContactProperties` node must be added at the WorldInfo level, not inside a robot node
