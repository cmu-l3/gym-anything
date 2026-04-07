#!/bin/bash
echo "=== Setting up sensor_housing_from_spec task ==="

source /workspace/scripts/task_utils.sh

mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

rm -f /home/ga/Documents/SolveSpace/sensor_housing.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/sensor_housing.dxf 2>/dev/null || true

date +%s > /tmp/sensor_housing_from_spec_start_ts

# Drop specification on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/sensor_housing_spec.txt << 'SPECEOF'
COMPONENT SPECIFICATION — SENSOR HOUSING CROSS-SECTION
Drawing No: INS-SH-0812
Revision: A
Material: 316L stainless steel (machined)
Application: Differential pressure transmitter housing, flanged inline type

SKETCH: Closed rectangular cross-section profile on XY plane.

GEOMETRY DESCRIPTION:
The housing cross-section is a stepped rectangle consisting of an outer body
and a narrower mounting boss. Draw the following profile as a closed polygon:

  A=(0, 0)        → B=(96, 0)      [bottom edge]
  B=(96, 0)       → C=(96, 48)     [right side, full height]
  C=(96, 48)      → D=(72, 48)     [top step right shoulder]
  D=(72, 48)      → E=(72, 80)     [boss right side]
  E=(72, 80)      → F=(24, 80)     [boss top]
  F=(24, 80)      → G=(24, 48)     [boss left side]
  G=(24, 48)      → H=(0, 48)      [top step left shoulder]
  H=(0, 48)       → A=(0, 0)       [left side, full height]

REQUIRED DIMENSIONAL CONSTRAINTS (5 total):
  1. Body width (A to B horizontal):    96 mm
  2. Body height (A to H vertical):     48 mm
  3. Boss width (G to D horizontal):    48 mm
  4. Boss height (D to E vertical):     32 mm
  5. Left boss offset (A to G horizontal): 24 mm

Tolerance: ±0.5 mm on all dimensions.

OUTPUTS REQUIRED:
  - Save as: /home/ga/Documents/SolveSpace/sensor_housing.slvs
  - Export DXF to: /home/ga/Documents/SolveSpace/sensor_housing.dxf

Issued by: Instrumentation Design Group
SPECEOF
chown ga:ga /home/ga/Desktop/sensor_housing_spec.txt

kill_solvespace

# Launch SolveSpace with no file (blank state for new sketch)
launch_solvespace
echo "Waiting for SolveSpace to open..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/sensor_housing_from_spec_start.png
echo "=== sensor_housing_from_spec setup complete ==="
echo "SolveSpace open with blank canvas. Spec file on Desktop."
