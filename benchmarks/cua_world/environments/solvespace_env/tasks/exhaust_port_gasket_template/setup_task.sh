#!/bin/bash
echo "=== Setting up exhaust_port_gasket_template task ==="

source /workspace/scripts/task_utils.sh

# Create workspace
mkdir -p /home/ga/Documents/SolveSpace
chown -R ga:ga /home/ga/Documents/SolveSpace

# Clear prior output files BEFORE recording timestamp
rm -f /home/ga/Documents/SolveSpace/exhaust_gasket.slvs 2>/dev/null || true
rm -f /home/ga/Documents/SolveSpace/exhaust_gasket.dxf 2>/dev/null || true

# Record start timestamp (anti-gaming)
date +%s > /tmp/exhaust_port_gasket_start_ts

# Place specification on Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/exhaust_port_gasket_spec.txt << 'SPECEOF'
EXHAUST PORT GASKET — CNC LASER CUTTING TEMPLATE
Part No: EG-3100-A    Rev: 01
Material: 2 mm Compressed Non-Asbestos Fiber Sheet
Application: Small-block engine exhaust port flange seal
==========================================================

OUTER BOUNDARY:
  Rectangle 150 mm wide x 120 mm tall
  Centered at drawing origin (0, 0)
  4 line segments forming a closed rectangle

EXHAUST PORT BORE (Egg-Shaped Opening):
  The port bore is wider at the bottom and narrower at the top,
  with smooth rounded transitions at the upper corners.

  Bottom arc:
    Semicircular arc, radius R = 20 mm
    Opens upward (concave side faces up)
    Centered on the vertical centerline of the gasket

  Top flat edge:
    Horizontal straight line, 30 mm long
    Centered on the vertical centerline above the bottom arc

  Upper corner fillets:
    Two fillet arcs, each with radius R = 8 mm
    Left fillet arc connects the left end of the top flat edge
      to the left end of the bottom semicircular arc — tangent to both
    Right fillet arc connects the right end of the top flat edge
      to the right end of the bottom semicircular arc — tangent to both

  The resulting closed bore profile consists of:
    1 semicircular arc (bottom, R=20)  +  1 straight line (top, 30mm)
    + 2 fillet arcs (upper corners, R=8 each)
  All four elements must connect tangentially for a smooth profile.

  Center the bore at the drawing origin.

BOLT CLEARANCE HOLES:
  4x holes, diameter 9 mm each
  Positions measured from the drawing center:
    Upper-right:  (+50, +40)
    Upper-left:   (-50, +40)
    Lower-right:  (+50, -40)
    Lower-left:   (-50, -40)

MODELING REQUIREMENTS:
  - All geometry in a single sketch on the XY workplane
  - Sketch must be fully constrained (0 degrees of freedom)
  - Extrude the profile to material thickness: 2 mm
  - Save model as: exhaust_gasket.slvs
  - Export DXF (AutoCAD 2007 format): exhaust_gasket.dxf
  - All output files in: ~/Documents/SolveSpace/

Tolerance: +/- 1.0 mm on all linear dimensions.
Issued by: Engine Gasket Design Group
SPECEOF
chown ga:ga /home/ga/Desktop/exhaust_port_gasket_spec.txt

# Launch SolveSpace on blank canvas
kill_solvespace

launch_solvespace
echo "Waiting for SolveSpace to open..."
wait_for_solvespace 30
sleep 5

maximize_solvespace
sleep 1

take_screenshot /tmp/exhaust_port_gasket_start.png
echo "=== exhaust_port_gasket_template setup complete ==="
echo "SolveSpace open blank. Spec file on Desktop."
