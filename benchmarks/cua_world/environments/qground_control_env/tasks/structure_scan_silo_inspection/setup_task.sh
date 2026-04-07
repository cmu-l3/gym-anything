#!/bin/bash
echo "=== Setting up structure_scan_silo_inspection task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write inspection brief document
cat > /home/ga/Documents/QGC/inspection_brief.txt << 'BRIEFDOC'
═══════════════════════════════════════════════════════
  GRAIN ELEVATOR STRUCTURAL INSPECTION — FLIGHT BRIEF
  Site: Cooperative Silo #4, Canberra Region
  Date: 2026-03-10
  Requested by: Allied Agricultural Insurance
═══════════════════════════════════════════════════════

STRUCTURE DETAILS
─────────────────
  Type:            Cylindrical grain elevator (steel)
  Approx. Center:  -35.3632° S, 149.1653° E
  Base Diameter:   ~12 meters
  Height:          28 meters (from grade to top cap)
  Damage Report:   Suspected dent/buckling on NW face
                   at ~18m elevation after recent storm

SCAN REQUIREMENTS
─────────────────
  Mission Type:    Structure Scan (multi-layer orbital)
  Minimum Layers:  3 (base, mid, top)
  Gimbal Pitch:    Near horizontal (0° ± 10°) for wall detail

CAMERA SPECIFICATION
────────────────────
  Model:           Sony α6000 (or manual equivalent)
  Sensor Size:     23.5 mm × 15.6 mm
  Image Resolution: 6000 × 4000 pixels
  Focal Length:    20 mm

FLIGHT CONSTRAINTS
──────────────────
  Takeoff:         Required as first mission item
  Return:          RTL (Return to Launch) after scan complete
  Max AGL:         40 meters

OUTPUT
──────
  Save mission as: /home/ga/Documents/QGC/silo_inspection.plan
═══════════════════════════════════════════════════════
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/inspection_brief.txt

# 3. Record task start time for mtime checks
date +%s > /tmp/task_start_time

# 4. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 5. Ensure QGC is running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== structure_scan_silo_inspection task setup complete ==="
echo "Brief document: /home/ga/Documents/QGC/inspection_brief.txt"
echo "Expected output: /home/ga/Documents/QGC/silo_inspection.plan"