#!/bin/bash
echo "=== Setting up swarm_drone_show_commissioning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write swarm specification document
cat > /home/ga/Documents/QGC/swarm_spec_sheet.txt << 'SPECDOC'
SWARM DRONE SHOW COMMISSIONING BRIEF
Vehicle: Drone #42
Fleet: Entertainment Swarm Alpha
Date: 2026-03-09

=== CRITICAL SAFETY DIRECTIVE ===
Standard survey UAV failsafes (like Return-to-Launch) are STRICTLY FORBIDDEN in dense drone show environments. A vehicle attempting to RTL will fly horizontally through the swarm grid, causing catastrophic mid-air collisions.

All failures must result in an immediate vertical descent ("Land in place").

=== PARAMETER CONFIGURATION ===
You must configure the following parameters in QGroundControl (Vehicle Setup > Parameters) for Drone #42:

1. Identification
   SYSID_THISMAV = 42

2. RC Loss Failsafe
   FS_THR_ENABLE = 3 (Always Land on RC loss)

3. GCS Failsafe
   FS_GCS_ENABLE = 0 (Disable standard GCS failsafe; managed by show controller)

4. Battery Failsafe
   BATT_FS_LOW_ACT = 1 (Always Land on low battery)

5. Geofence Actions
   FENCE_ACTION = 2 (Always Land on geofence breach)
   FENCE_RADIUS = 150 (Tight cylindrical containment in meters)
   FENCE_ALT_MAX = 120 (Regulatory maximum altitude in meters)

6. LED Configuration
   NTF_LED_TYPES = 255 (Enable all custom LED protocols for the show)

=== REQUIRED DELIVERABLES ===
1. Apply all 8 parameters above to the live vehicle.
2. Export the full parameter list using QGC's "Tools -> Save to file" option to:
   /home/ga/Documents/QGC/vehicle42_show.params
3. Write a commissioning sign-off report at:
   /home/ga/Documents/QGC/signoff.txt

The sign-off report must explicitly state that Vehicle 42 has been commissioned and that all failsafes are set to "Land in place".
SPECDOC

chown ga:ga /home/ga/Documents/QGC/swarm_spec_sheet.txt

# Remove any pre-existing output files
rm -f /home/ga/Documents/QGC/vehicle42_show.params
rm -f /home/ga/Documents/QGC/signoff.txt

# 3. Reset parameters to standard defaults (differs from show specs so do-nothing fails)
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)
        defaults = {
            b'SYSID_THISMAV': 1.0,
            b'FS_THR_ENABLE': 1.0,
            b'FS_GCS_ENABLE': 1.0,
            b'BATT_FS_LOW_ACT': 0.0,
            b'FENCE_ACTION': 0.0,
            b'FENCE_RADIUS': 300.0,
            b'FENCE_ALT_MAX': 100.0,
            b'NTF_LED_TYPES': 199.0,
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

echo "=== swarm_drone_show_commissioning task setup complete ==="