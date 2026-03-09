# Task: Configure Vehicle Sensors

## Overview

**Difficulty**: Hard
**Occupation**: Autonomous Vehicle Simulation Engineer
**Industry**: Automotive R&D / Self-Driving Vehicle Technology
**Environment**: Webots 3D Robot Simulator

## Domain Context

Autonomous vehicle simulation engineers use Webots to validate sensor fusion algorithms before deploying software on physical vehicles. A critical step is ensuring the simulated sensors match the hardware specification precisely — mismatched resolution or range parameters produce training data that does not transfer to the real platform.

This task presents a real-world scenario: a new AV test platform world has been configured with placeholder sensor values during initial world construction. Before running perception pipeline validation, the sensors must be reconfigured to exactly match the hardware specs of the Velodyne VLP-16 LIDAR and the vehicle's front camera.

## Task Goal

Configure a Webots autonomous vehicle simulation to use correct sensor specifications:

1. **Front Camera** (`front_camera`): Set resolution to **640×480** (currently misconfigured at 128×64)
2. **Velodyne LIDAR** (`velodyne_lidar`): Set `numberOfLayers` to **16** and `maxRange` to **100** meters (currently 4 layers, 20m range — wrong for VLP-16)
3. **GPS**: Already present and correctly configured — do not modify

Save the corrected world to **`/home/ga/Desktop/av_sensors_configured.wbt`**

## Starting State

The world file `data/av_scenario.wbt` is loaded in Webots. The AV platform robot (`DEF AV_PLATFORM Robot`) contains:
- Camera `front_camera`: width=128, height=64 (WRONG — too low for visual odometry)
- Lidar `velodyne_lidar`: numberOfLayers=4, maxRange=20 (WRONG — should be VLP-16 spec)
- GPS `gps`: correct (do not modify)

## Hardware Reference

**Velodyne VLP-16 LIDAR** (industry-standard AV sensor):
- 16 laser channels (layers)
- 360° horizontal FOV
- 100m maximum range
- 10 Hz rotation speed

**Automotive Camera** (standard AV forward camera):
- 640×480 resolution minimum for visual odometry
- 60° horizontal FOV
- Near/far clipping as configured

## Success Criteria

The saved world at `/home/ga/Desktop/av_sensors_configured.wbt` must contain:
1. Camera `width 640` — 20 points
2. Camera `height 480` — 20 points
3. Lidar `numberOfLayers 16` — 25 points
4. Lidar `maxRange 100` — 25 points
5. File exists at correct path — 10 points

**Pass threshold**: 70/100 points

## Verification Strategy

The verifier copies the saved `.wbt` file from the VM and uses regex pattern matching to find the specific field values within the camera and lidar node definitions. The patterns checked are:
- `width 640` (camera width)
- `height 480` (camera height)
- `numberOfLayers 16` (lidar layers)
- `maxRange 100` (lidar range)

## Features Exercised

| Feature | Description |
|---------|-------------|
| Scene tree navigation | Expand robot node, find named sensor children |
| Camera node editing | Modify width, height fields |
| Lidar node editing | Modify numberOfLayers, maxRange fields |
| File > Save World As | Save modified world to specific path |

## Edge Cases

- The agent may accidentally modify the wrong sensor (e.g., confusing camera and lidar nodes)
- The agent must navigate to the correct robot and find the specific named sensors
- The verifier uses exact string matching so values must be exact integers (640, 480, 16, 100)
