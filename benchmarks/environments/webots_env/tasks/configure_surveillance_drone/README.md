# Task: Configure Surveillance Drone

## Overview

**Difficulty**: Hard
**Occupation**: UAV Systems Engineer
**Industry**: Emergency Services / Public Safety / Environmental Monitoring
**Environment**: Webots 3D Robot Simulator

## Domain Context

UAV systems engineers use Webots to validate drone sensor configurations before deploying surveillance systems for emergency services (fire departments, search and rescue teams, law enforcement). Before any field deployment, the simulation must match the exact hardware configuration including camera resolution, field of view, GPS availability, and operating altitude.

This task represents a real pre-deployment validation workflow: the drone simulation has been initially set up with placeholder values. The engineer must configure the sensors to match deployment specifications defined by the emergency services protocol.

## Task Goal

Configure a surveillance drone simulation world:

1. **Surveillance Camera** (`surveillance_camera`): Set resolution to **width=1280, height=720** (HD standard for surveillance). Set `fieldOfView` to **0.7854 radians** (45°, narrow FOV for targeted ground monitoring)
2. **GPS Sensor**: Add a GPS node to the drone's children. Name it `gps`. (Currently missing — prevents geo-tagging)
3. **Operating Altitude**: Set the `SURVEILLANCE_DRONE` robot's Z translation to **5.0 meters** (minimum legal operating altitude; currently set to 0.5m near-ground)

Save the configured world to **`/home/ga/Desktop/surveillance_drone.wbt`**

## Starting State

The world file `data/drone_scenario.wbt` is loaded in Webots with:
- Camera `surveillance_camera`: width=320, height=240, fieldOfView=1.5708 rad (90°) — all wrong
- No GPS sensor on the drone
- `SURVEILLANCE_DRONE` translation Z = 0.5 (near ground — wrong altitude)

## Sensor Specifications Reference

**Surveillance Camera** (emergency services standard):
- Minimum resolution for object identification: 1280×720 (HD)
- Field of view: 45° (0.7854 rad) for targeted monitoring
- Wide-angle (90°) is not suitable for ground surveillance from altitude

**GPS for Surveillance UAV**:
- Required for geo-tagged imagery compliance
- Node type: `GPS` with name `gps`

**Operational Parameters**:
- Minimum safe altitude: 5.0m above ground level

## Success Criteria

The saved world at `/home/ga/Desktop/surveillance_drone.wbt` must contain:
1. File exists at correct path — 10 points
2. Camera `width 1280` — 20 points
3. Camera `height 720` — 20 points
4. Camera fieldOfView between 0.6 and 0.9 (45° ± tolerance) — 20 points
5. A `GPS` node is present under the drone robot — 10 points
6. Drone translation Z between 4.0 and 6.0 (5m ± 1m tolerance) — 20 points

**Pass threshold**: 70/100 points

## Verification Strategy

The verifier:
1. Copies the saved `.wbt` file from the VM
2. Checks camera width/height values via regex
3. Checks camera fieldOfView value
4. Checks for GPS node presence anywhere in the file
5. Extracts the SURVEILLANCE_DRONE translation Z component

## Features Exercised

| Feature | Description |
|---------|-------------|
| Scene tree navigation | Find drone robot and expand its children |
| Camera node editing | Modify width, height, and fieldOfView |
| Add sensor node | Add GPS node to robot's children list |
| Robot translation editing | Modify translation Z for altitude |
| File > Save World As | Save modified world to specific path |

## Edge Cases

- Adding a GPS node requires using the scene tree's "Add node" functionality (not just editing existing fields)
- The agent must change THREE distinct aspects of the camera (width, height, fieldOfView)
- The agent must distinguish between robot translation Z and the camera's translation Z
