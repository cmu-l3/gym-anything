#!/bin/bash
echo "=== Setting up vehicle_inspection_report task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write inspection template document
cat > /home/ga/Documents/QGC/inspection_template.txt << 'TMPDOC'
UAV FLEET VEHICLE INSPECTION TEMPLATE
Vehicle ID: AC-SITL-007
Fleet: Zurich Agricultural Survey Fleet
Inspection Date: 2026-03-09
Inspector: (Your name / role)

=== SECTION 1: FLIGHT MODE CONFIGURATION ===

Program the 6 flight mode slots to the FLEET STANDARD configuration below.
Use Vehicle Setup > Parameters in QGC, search for each FLTMODE parameter.

  FLTMODE1 = 2   (AltHold  — primary manual flight mode)
  FLTMODE2 = 5   (Loiter   — GPS-assisted hold, for precision hovering)
  FLTMODE3 = 3   (Auto     — autonomous mission execution)
  FLTMODE4 = 6   (RTL      — Return to Launch on switch)
  FLTMODE5 = 9   (Land     — immediate landing)
  FLTMODE6 = 16  (PosHold  — position hold with manual override)

Mode number reference:
  0=Stabilize, 2=AltHold, 3=Auto, 4=Guided, 5=Loiter, 6=RTL,
  9=Land, 16=PosHold, 17=Brake, 21=Smart_RTL

=== SECTION 2: ATTITUDE CONTROLLER TUNING ===

Set attitude P-gains to the fleet standard (slightly conservative for ag payload):

  ATC_ANG_RLL_P = 4.0   (roll angle P gain, default is 4.5 — reduce slightly)
  ATC_ANG_PIT_P = 4.0   (pitch angle P gain, default is 4.5 — reduce slightly)

Search for "ATC_ANG_RLL_P" and "ATC_ANG_PIT_P" in Parameters.

=== SECTION 3: MAVLink TELEMETRY VERIFICATION ===

Use QGC Analyze View > MAVLink Inspector to verify live telemetry:
1. Click the QGC icon top-left > Analyze Tools > MAVLink Inspector
2. Find the GPS_RAW_INT or GLOBAL_POSITION_INT message
3. Read the current GPS latitude and longitude values
4. Note: SITL simulates a vehicle near Zurich (approx. 47.39°N, 8.54°E)

=== SECTION 4: INSPECTION REPORT ===

After completing all configuration steps, write a plain text inspection report
to /home/ga/Documents/QGC/inspection_report.txt

The report MUST include:
  - All 6 flight mode assignments (slot number AND mode name)
  - The ATC gain values you set
  - GPS coordinates read from MAVLink Inspector (lat/lon)
  - An airworthiness statement (e.g., "Vehicle is airworthy for survey operations")

Example report format:
---
Vehicle Inspection Report — AC-SITL-007 — 2026-03-09

Flight Modes:
  FLTMODE1: AltHold (2)
  FLTMODE2: Loiter (5)
  FLTMODE3: Auto (3)
  FLTMODE4: RTL (6)
  FLTMODE5: Land (9)
  FLTMODE6: PosHold (16)

ATC Gains:
  ATC_ANG_RLL_P: 4.0
  ATC_ANG_PIT_P: 4.0

GPS Position (from MAVLink Inspector):
  Latitude:  47.397750
  Longitude: 8.545607

Airworthiness: Vehicle is airworthy and cleared for agricultural survey operations.
---
TMPDOC

chown ga:ga /home/ga/Documents/QGC/inspection_template.txt

# 3. Reset flight modes and ATC gains to defaults so do-nothing = 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up: let MAVLink channel stabilize
        # Reset flight modes to default (0=Stabilize) — all different from required
        defaults = {
            b'FLTMODE1': 0.0,
            b'FLTMODE2': 0.0,
            b'FLTMODE3': 0.0,
            b'FLTMODE4': 0.0,
            b'FLTMODE5': 0.0,
            b'FLTMODE6': 0.0,
            b'ATC_ANG_RLL_P': 4.5,
            b'ATC_ANG_PIT_P': 4.5,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing inspection report
rm -f /home/ga/Documents/QGC/inspection_report.txt

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 7. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== vehicle_inspection_report task setup complete ==="
echo "Template: /home/ga/Documents/QGC/inspection_template.txt"
echo "Expected output: /home/ga/Documents/QGC/inspection_report.txt"
