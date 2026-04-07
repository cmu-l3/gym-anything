# Functional Check Flight (`functional_check_flight@1`)

## Overview

This task tests the agent's ability to execute a real-time flight operation using QGroundControl's Fly View — arming the simulated vehicle, commanding takeoff to a specified altitude, holding position, commanding return-to-launch, and documenting the flight in a post-flight check report. Unlike all other tasks which test planning or configuration, this task requires live vehicle interaction through the SITL simulator.

## Rationale

**Why this task is valuable:**
- Tests the Fly View interface — the primary operational screen of QGC
- Requires real-time interaction with a simulated vehicle (arm, takeoff, RTL)
- Evaluates understanding of UAV flight procedures and safety protocols
- Combines live telemetry observation with documentation
- Verifiable through multiple independent signals (flight logs, parameters, VLM trajectory)

**Real-world Context:** An Agricultural Technician has just configured a new ArduCopter for crop monitoring. Before deploying it over a customer's field, company SOPs require a "functional check flight" — a short hover test at 25 m to confirm GPS hold, altitude stability, and RTL behavior. The technician must arm the vehicle, verify it reaches target altitude, confirm it holds position, command RTL, watch it land safely, and fill out the post-flight check form.

## Task Description

**Goal:** Execute a functional check flight using QGroundControl's Fly View: arm the SITL-simulated ArduCopter, take off to 25 m altitude, observe position hold, command Return-to-Launch, wait for landing, then write a post-flight check report documenting the flight.

**Starting State:** QGroundControl is open in Fly View, connected to an ArduCopter SITL instance. The vehicle is disarmed on the ground. A pre-flight procedure document is at `/home/ga/Documents/QGC/preflight_procedure.txt`.

**Expected Actions:**
1. Read the pre-flight procedure at `/home/ga/Documents/QGC/preflight_procedure.txt`
2. In QGC Fly View, arm the vehicle
3. Command takeoff to **25 m** altitude
4. After the vehicle reaches altitude, observe the telemetry for approximately 15 seconds
5. Command **RTL** (Return to Launch)
6. Wait for the vehicle to descend, land, and auto-disarm
7. Write a post-flight check report to `/home/ga/Documents/QGC/check_flight_report.txt`

**Final State:** The vehicle is disarmed and on the ground. The SITL has recorded flight time > 0. A post-flight check report exists with the required telemetry details.

## Verification Strategy

### Primary Verification: SITL Flight Telemetry via pymavlink
The `export_result.sh` script connects to SITL and queries:
- `STAT_FLTTIME`: Total flight time in seconds (>0 means vehicle flew)
- `STAT_RUNTIME`: Total armed time in seconds
- Current armed state (should be disarmed = landed)

### Secondary Verification: VLM Trajectory Analysis
The verifier samples frames from the agent's trajectory and asks a Vision-Language Model to visually confirm:
- The drone took off and the HUD altitude climbed to ~25m
- The flight mode transitioned to RTL/Land

### Tertiary Verification: Report Content
The verifier parses the check report text file for:
- Altitude value (decimal number near 25)
- GPS coordinate patterns
- Airworthiness determination keyword

### Scoring System
| Criterion | Points | Description |
|-----------|--------|-------------|
| STAT_FLTTIME increased | 20 | Vehicle actually flew (physics engine recorded flight) |
| STAT_RUNTIME increased | 10 | Vehicle was armed |
| Vehicle disarmed at end | 10 | Vehicle successfully landed and disarmed |
| VLM Verified Sequence | 30 | Visual trajectory shows Takeoff -> ~25m -> RTL/Land |
| Report file created | 10 | File exists and modified during task |
| Report has target altitude| 10 | Pattern match for ~25m altitude |
| Report has GPS / PASS | 10 | Lat/Lon and "PASS" determination present |
| **Total** | **100** | |

Pass Threshold: 70 points