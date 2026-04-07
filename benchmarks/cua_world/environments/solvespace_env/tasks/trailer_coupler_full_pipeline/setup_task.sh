#!/bin/bash
echo "=== Setting up trailer_coupler_full_pipeline task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/coupler_beam.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/coupler_beam.dxf 2>/dev/null || true

date +%s > /tmp/trailer_coupler_full_pipeline_start_ts

# Drop specification on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/coupler_beam_spec.txt << 'SPECEOF'
COMPONENT SPECIFICATION — TRAILER COUPLER U-CHANNEL BEAM
Drawing No: TRL-CB-1184
Revision: B
Material: S355 structural steel, hot-rolled
Application: 5th wheel king-pin coupler frame longitudinal beam

SKETCH: U-channel cross-section on XY plane (open at top).

GEOMETRY DESCRIPTION:
Draw the following 6-line open profile (U-shape) — NOT a closed polygon.
The open top will be used for the extrusion profile.

  A=(0, 0)     → B=(180, 0)   [bottom flange]
  B=(180, 0)   → C=(180, 120) [right web]
  C=(180, 120) → D=(160, 120) [right flange top step]
  D=(160, 120) → E=(20, 120)  [right to left at flange top — construction only]
  ... Actually: draw the CLOSED outer U-profile including flanges:

CLOSED PROFILE (8 lines):
  A=(0, 0)     → B=(180, 0)    bottom
  B=(180, 0)   → C=(180, 120)  right web
  C=(180, 120) → D=(160, 120)  right flange
  D=(160, 120) → E=(160, 12)   right inner step
  E=(160, 12)  → F=(20, 12)    inner bottom
  F=(20, 12)   → G=(20, 120)   left inner step
  G=(20, 120)  → H=(0, 120)    left flange
  H=(0, 120)   → A=(0, 0)      left web

REQUIRED DIMENSIONAL CONSTRAINTS (5 total):
  1. Overall width (A to B):       180 mm
  2. Web height (A to C vertical):  120 mm
  3. Flange width (C to D):          20 mm
  4. Wall thickness (E to F):        12 mm  (A to E vertical distance = 12 mm)
  5. Inner width (E to F horizontal): 140 mm

EXTRUSION:
  After sketching and constraining, extrude the closed profile.
  Extrusion depth: 800 mm (enter this value in the extrude dialog).

OUTPUTS REQUIRED:
  - Save file as: /home/ga/Documents/SolveSpace/coupler_beam.slvs
  - Export DXF of the sketch to: /home/ga/Documents/SolveSpace/coupler_beam.dxf

Tolerance: ±0.5 mm on all linear dimensions.
Issued by: Trailer Frame Design Department
SPECEOF
chown ga:ga /home/ga/Desktop/coupler_beam_spec.txt

kill_solvespace

launch_solvespace
echo "Waiting for SolveSpace to open..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/trailer_coupler_full_pipeline_start.png
echo "=== trailer_coupler_full_pipeline setup complete ==="
echo "SolveSpace open blank. Spec file on Desktop."
