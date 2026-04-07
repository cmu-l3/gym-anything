# geofence_safety_setup

**Difficulty**: very_hard
**Environment**: qground_control_env
**Primary Occupation**: Agricultural UAV Operator / Drone Safety Officer

## Task Overview

A licensed Agricultural UAV Operator must configure complete airspace safety geofencing in QGroundControl before a crop-spray campaign. The task spans multiple QGC features (Fence tools, Rally Points, Vehicle Parameters) and requires reading an operations brief to determine the correct coordinates and parameter values.

## Domain Context

Agricultural drone operators in Switzerland must comply with EASA regulations requiring clearly defined inclusion and exclusion zones for any commercial UAV operation. Failure to configure geofencing means the drone could enter restricted airspace (over roads, buildings, power infrastructure) or lose the vehicle if it exceeds boundaries without an appropriate return action. This is a real pre-flight compliance requirement, not a theoretical exercise.

## Goal (End State)

1. A QGC `.plan` file at `/home/ga/Documents/QGC/safety_fence.plan` containing:
   - An **inclusion polygon** with ≥5 vertices enclosing the approved agricultural field
   - An **exclusion zone** (polygon or circle) around the power substation
   - ≥2 **rally points** at safe emergency landing locations

2. Two ArduPilot parameters set:
   - `FENCE_ACTION = 1` (RTL on fence breach, NOT the default 0=report only)
   - `RTL_ALT = 2500` (25 m return altitude)

All coordinates and parameter values are in the operations brief at `/home/ga/Documents/QGC/ops_brief.txt`.

## Verification Strategy

The verifier parses the `.plan` JSON and queries pymavlink for parameters:
1. **File exists** (10 pts): Plan file at expected path
2. **Modified during task** (10 pts): File mtime ≥ task start time
3. **Inclusion polygon ≥5 vertices** (25 pts): `inclusion=true` polygon with ≥5 path points; partial (10 pts) for 3-4 vertices
4. **Exclusion zone present** (20 pts): Polygon/circle with `inclusion=false` in geoFence section
5. **≥2 rally points** (20 pts): `rallyPoints.points` array has ≥2 entries; partial (8 pts) for exactly 1
6. **FENCE_ACTION == 1** (5 pts): Live pymavlink query
7. **RTL_ALT == 2500** (10 pts): Live pymavlink query (±50 cm tolerance)

**Pass threshold**: 70

## Anti-Gaming Analysis

- **Do-nothing**: No file → score=0
- **File with no exclusion**: max 10+10+25+0+20+5+10=80 but missing exclusion means 80-20=60 < 70 → fails
- **Missing rally points**: 10+10+25+20+0+5+10=80 → passes — acceptable; rally points are supplementary
- **Full completion**: 100 pts

## Key Technical Details

- QGC `.plan` format: `geoFence.polygons` array, each has `inclusion` bool and `path` coordinate array
- Rally points: `rallyPoints.points` array of `[lat, lon, alt]` triples
- Exclusion circles: `geoFence.circles` array with `inclusion: false` and `radius`
- FENCE_ACTION=0 (default) only reports violations; FENCE_ACTION=1 triggers RTL

## Files

- `task.json`: Task definition, 80 steps, 800s timeout
- `setup_task.sh`: Creates `ops_brief.txt`, ensures SITL+QGC running
- `export_result.sh`: Stats file, embeds plan JSON, queries pymavlink for 2 params
- `verifier.py`: Parses fence plan + checks pymavlink parameter values
