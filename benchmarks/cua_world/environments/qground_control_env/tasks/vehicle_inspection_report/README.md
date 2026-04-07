# vehicle_inspection_report

**Difficulty**: very_hard
**Environment**: qground_control_env
**Primary Occupation**: UAV Fleet Manager / Aviation Safety Inspector

## Task Overview

A UAV Fleet Manager must complete a full pre-deployment commissioning inspection of an ArduCopter vehicle. The task spans three distinct QGC feature areas: Vehicle Parameters (flight modes + attitude gains), Analyze View / MAVLink Inspector (live telemetry), and text file creation (inspection report). The agent must read the inspection template, configure the vehicle to fleet standard, verify telemetry, and write a report.

## Domain Context

Fleet managers maintain configuration consistency across all vehicles in a survey fleet. Before any vehicle enters service, it undergoes a commissioning inspection: flight modes must be programmed to the fleet standard (so all pilots can use any vehicle interchangeably), gains must be tuned (heavier payloads require softer P-gains), GPS lock must be confirmed via MAVLink, and the inspection is documented for regulatory compliance. This is standard practice in commercial UAV operations worldwide.

## Goal (End State)

1. **Flight modes configured** (6 FLTMODE parameters set to fleet standard):
   - FLTMODE1=2 (AltHold), FLTMODE2=5 (Loiter), FLTMODE3=3 (Auto)
   - FLTMODE4=6 (RTL), FLTMODE5=9 (Land), FLTMODE6=16 (PosHold)

2. **ATC gains set** (both within ±0.2 of 4.0):
   - ATC_ANG_RLL_P ∈ [3.8, 4.2]
   - ATC_ANG_PIT_P ∈ [3.8, 4.2]

3. **Inspection report** at `/home/ga/Documents/QGC/inspection_report.txt` containing:
   - All 6 flight mode assignments with mode names
   - ATC gain values set
   - GPS coordinates read from MAVLink Inspector
   - An airworthiness statement

The agent must discover all required values from the inspection template at `/home/ga/Documents/QGC/inspection_template.txt`.

## Verification Strategy

`export_result.sh` queries 8 parameters via pymavlink AND stats the report file:
1. **FLTMODE1=2** (10 pts), **FLTMODE2=5** (10 pts), **FLTMODE3=3** (10 pts)
2. **FLTMODE4=6** (8 pts), **FLTMODE5=9** (8 pts), **FLTMODE6=16** (7 pts)
3. **ATC_ANG_RLL_P ∈ [3.8, 4.2]** (8 pts)
4. **ATC_ANG_PIT_P ∈ [3.8, 4.2]** (8 pts)
5. **Report exists + modified during task** (15 pts)
6. **Report size > 200 bytes** (4 pts)
7. **Mode names in report** (7 pts): ≥4 of: althold, loiter, auto, rtl, land, poshold
8. **GPS coordinates in report** (5 pts): decimal latitude/longitude pattern

**Pass threshold**: 75

## Anti-Gaming Analysis

| Strategy | Score | Pass? |
|----------|-------|-------|
| Do-nothing (all defaults) | 0 | No |
| All modes wrong (default 0), correct gains, full report | 0+8+8+15+4+7+5 = 47 | No |
| 4 modes correct, no ATC, no report | 10+10+10+8+0+0+0+0 = 38 | No |
| All modes + ATC correct, no report | 53+16 = 69 | No |
| All modes + ATC correct + report exists | 53+16+15+4+7+5 = 100 | Yes |
| Full completion | 100 | Yes |

Default FLTMODE=0 (Stabilize) differs from all required values, so do-nothing always scores 0. The threshold of 75 enforces that agents must produce the inspection report (max without report = 69 < 75).

## Key Technical Details

- Flight mode numbers: 2=AltHold, 3=Auto, 5=Loiter, 6=RTL, 9=Land, 16=PosHold
- Default ATC_ANG_RLL_P = ATC_ANG_PIT_P = 4.5 (fleet standard requires 4.0 for heavier payload)
- SITL GPS position: ~47.3977°N, 8.5456°E (near Zurich, Switzerland)
- MAVLink Inspector: accessible via Analyze menu → MAVLink Inspector

## Files

- `task.json`: Task definition, 80 steps, 800s timeout
- `setup_task.sh`: Creates `inspection_template.txt`, resets all 8 params to defaults, removes any pre-existing report
- `export_result.sh`: Queries 8 params via pymavlink, stats report file, embeds report content
- `verifier.py`: Checks parameter values + report content (mode names, GPS coords)
