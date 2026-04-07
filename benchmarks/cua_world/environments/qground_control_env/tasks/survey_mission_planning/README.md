# survey_mission_planning

**Difficulty**: very_hard
**Environment**: qground_control_env
**Primary Occupation**: Remote Sensing Scientist ($46.7M GDP)

## Task Overview

A Remote Sensing Scientist must plan a photogrammetric survey mission for precision agriculture using QGroundControl. The agent must locate the survey requirements document, parse the camera and flight specifications, then configure a Survey mission in QGC's Plan View that meets the contracted Ground Sampling Distance and overlap requirements.

## Domain Context

Remote Sensing Scientists use UAV photogrammetry to generate orthomosaics and Digital Surface Models (DSMs) for crop health monitoring, yield estimation, and precision-spray planning. GSD (Ground Sampling Distance) is the critical quality metric — it determines the spatial resolution of the output products. Achieving the correct altitude and overlap percentages is non-negotiable: too low and the files are rejected by the processing pipeline; too high and features below the resolution threshold are undetectable.

## Goal (End State)

A QGC `.plan` file at `/home/ga/Documents/QGC/field_survey.plan` containing a Survey ComplexItem with:
- Camera configured for Sony α5100 (23.5mm × 15.6mm sensor, 6000×4000px, 16mm focal length)
- Altitude achieving 4 cm/pixel GSD: **≈163.4 m** (acceptable: 140–190 m)
- FrontalOverlap: **75%** (acceptable: 60–90%)
- SideOverlap: **65%** (acceptable: 50–80%)

The agent must discover all values by reading the requirements document at `/home/ga/Documents/QGC/survey_requirements.txt`.

## Verification Strategy

The verifier parses the `.plan` JSON directly via `copy_from_env`:
1. **File exists** (15 pts): Plan file at expected path
2. **Modified during task** (10 pts): File mtime ≥ task start time
3. **Survey ComplexItem found** (30 pts): `complexItemType == "survey"` present in items tree
4. **Altitude in [140, 190] m** (25 pts): `distanceToSurface` or equivalent field in range
5. **FrontalOverlap in [60, 90]** (10 pts): `FrontalOverlap` key value in range
6. **SideOverlap in [50, 80]** (10 pts): `SideOverlap` key value in range

**Pass threshold**: 80 (requires correct altitude — max without altitude = 75 < 80)

## Anti-Gaming Analysis

- **Do-nothing**: No file → score=0
- **Wrong altitude** (e.g., 50m): Gets 15+10+30+10+10=75 → fails (75 < 80)
- **Survey with correct altitude, wrong overlaps**: 15+10+30+25=80 → passes (acceptable — altitude is the primary spec)
- **Full completion**: 100 pts

## Key Technical Details

- GSD formula: `altitude = GSD × focal_length × image_width / sensor_width = 0.04 × 16 × 6000 / 23.5 = 163.4 m`
- QGC Survey pattern saves `complexItemType: "survey"` in the plan JSON
- The `CameraCalc` nested object contains `FrontalOverlap`, `SideOverlap`, `distanceToSurface`
- Verifier uses recursive key search to handle QGC version differences in nesting

## Files

- `task.json`: Task definition, 80 steps, 800s timeout
- `setup_task.sh`: Creates `survey_requirements.txt`, ensures SITL+QGC running
- `export_result.sh`: Stats the plan file, embeds content as JSON string
- `verifier.py`: Parses plan JSON, checks survey item + altitude + overlaps
