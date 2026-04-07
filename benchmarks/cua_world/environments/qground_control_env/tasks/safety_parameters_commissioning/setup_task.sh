#!/bin/bash
echo "=== Setting up safety_parameters_commissioning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write safety commissioning checklist
cat > /home/ga/Documents/QGC/safety_checklist.txt << 'CHECKDOC'
ARDUPILOT SAFETY COMMISSIONING CHECKLIST
Vehicle: ArduCopter (SITL — pre-deployment audit)
Auditor: Safety Officer
Date: 2026-03-09
Reference: ArduCopter Operations Manual v4.5

=== MANDATORY PARAMETER SETTINGS ===

All parameters below MUST be set before this vehicle is cleared for flight.
Current values are all factory defaults and are NOT acceptable for operations.

---
PARAMETER 1: FS_BATT_ENABLE
  Description: Battery failsafe action on low battery
  Current default: 0 (disabled — UNSAFE)
  Required value: 2
  Meaning: Value 2 = Land immediately on low battery
  Why: Disabling battery failsafe risks fly-away or crash on depletion.

---
PARAMETER 2: RTL_ALT
  Description: Return-to-launch altitude (centimetres)
  Current default: 1500 (15 m — too low for obstacle clearance)
  Required value: 2500
  Meaning: 2500 cm = 25 m above launch point during RTL
  Why: 15 m is insufficient for tree/building clearance in agricultural areas.

---
PARAMETER 3: FENCE_ENABLE
  Description: Enable geofence enforcement
  Current default: 0 (disabled)
  Required value: 1
  Meaning: Value 1 = Geofence active and enforced
  Why: Geofence must be active to prevent incursions into restricted airspace.

---
PARAMETER 4: FENCE_ALT_MAX
  Description: Maximum altitude fence ceiling (centimetres)
  Current default: 10000 (100 m — too high)
  Required value: 8000
  Meaning: 8000 cm = 80 m altitude ceiling
  Why: Local regulations limit agricultural operations to 80 m AGL.

---
PARAMETER 5: FS_GCS_ENABLE
  Description: GCS heartbeat failsafe (lost link action)
  Current default: 0 (disabled — UNSAFE)
  Required value: 1
  Meaning: Value 1 = RTL when GCS heartbeat lost for >5 seconds
  Why: Lost link with no failsafe means uncontrolled vehicle.

---
PARAMETER 6: LAND_SPEED_HIGH
  Description: High-altitude phase landing descent speed (cm/s)
  Current default: 0 (uses LAND_SPEED for entire descent — too slow above 10m)
  Required value: 150
  Meaning: 150 cm/s = 1.5 m/s descent speed for altitudes above 10 m
  Why: Faster initial descent reduces time in hazardous hover-descent phase.

=== HOW TO SET PARAMETERS IN QGC ===
1. Click the Q icon (top-left of QGC toolbar)
2. Click Vehicle Setup (wrench icon)
3. Click "Parameters" in the left sidebar
4. Type the parameter name in the search box (e.g. "FS_BATT")
5. Click on the parameter row to select it
6. Enter the new value in the edit field
7. Click "Set" or press Enter
8. The value is sent to the vehicle immediately via MAVLink

Set ALL 6 parameters before the audit is complete.
CHECKDOC

chown ga:ga /home/ga/Documents/QGC/safety_checklist.txt

# 3. Reset all target parameters to defaults so do-nothing = 0 pts
# This ensures factory defaults differ from required values
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
        # Reset to known defaults that differ from required values
        defaults = {
            b'FS_BATT_ENABLE': 0.0,
            b'RTL_ALT': 1500.0,
            b'FENCE_ENABLE': 0.0,
            b'FENCE_ALT_MAX': 10000.0,
            b'FS_GCS_ENABLE': 0.0,
            b'LAND_SPEED_HIGH': 0.0,
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

# 4. Record task start time
date +%s > /tmp/task_start_time

# 5. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== safety_parameters_commissioning task setup complete ==="
echo "Checklist: /home/ga/Documents/QGC/safety_checklist.txt"
