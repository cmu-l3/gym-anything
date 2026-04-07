#!/bin/bash
echo "=== Setting up bvlos_smart_rtl_failsafe_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write BVLOS safety directive
cat > /home/ga/Documents/QGC/bvlos_safety_directive.txt << 'SAFEDOC'
BVLOS SMART RTL SAFETY DIRECTIVE
Operation: Powerline Inspection Sector 4 (Zurich)
Operator: Utility Drone Ops
Date: 2026-03-10

=== CRITICAL HAZARD WARNING ===
Standard straight-line RTL is STRICTLY PROHIBITED in this sector.
A straight RTL will cause the UAV to strike the high-voltage transmission lines.
The vehicle MUST be configured to use "Smart RTL" (SmartRTL), which forces
the drone to safely retrace its exact outbound path if a failsafe is triggered.

=== REQUIRED PARAMETER CONFIGURATION ===
Use QGroundControl's Vehicle Setup > Parameters menu to configure the following
failsafe parameters on the flight controller:

1. FS_GCS_ENABLE = 3
   (Action: SmartRTL or RTL on ground station communication loss)

2. BATT_FS_LOW_ACT = 3
   (Action: SmartRTL or RTL on low battery)

3. FS_THR_ENABLE = 4
   (Action: SmartRTL or RTL on radio control/throttle loss)

4. SRTL_POINTS = 500
   (Increases the Smart RTL breadcrumb path buffer to 500 points for a longer route)

5. SRTL_ACCURACY = 1
   (Increases breadcrumb precision to 1 meter)

=== RALLY POINTS (EMERGENCY LANDING ZONES) ===
If the vehicle cannot make it all the way home, it needs safe alternative
landing locations along the corridor.

Switch to QGC's Plan View. Select the Rally Point tool (flag icon) and place
exactly 2 Rally Points at the following coordinates:
  - Alpha Landing Zone:  Lat 47.3980, Lon 8.5450
  - Bravo Landing Zone:  Lat 47.3990, Lon 8.5470
  
(Altitude is not strictly evaluated, but default 50m is fine)

=== REQUIRED DELIVERABLE ===
Save your plan containing the Rally Points to:
/home/ga/Documents/QGC/bvlos_failsafe.plan

Ensure the plan file is saved and all 5 parameters are successfully written
to the vehicle before closing the application.
SAFEDOC

chown ga:ga /home/ga/Documents/QGC/bvlos_safety_directive.txt

# 3. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to incorrect defaults so "do nothing" fails
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
        
        # Reset to dangerous/incorrect defaults
        defaults = {
            b'FS_GCS_ENABLE': 0.0,      # Disabled
            b'BATT_FS_LOW_ACT': 0.0,    # Disabled
            b'FS_THR_ENABLE': 1.0,      # Standard RTL
            b'SRTL_POINTS': 300.0,      # Standard buffer
            b'SRTL_ACCURACY': 2.0,      # Standard accuracy
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to unsafe defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Clean up any previous attempts
rm -f /home/ga/Documents/QGC/bvlos_failsafe.plan

# 6. Record task start time
date +%s > /tmp/task_start_time

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

echo "=== bvlos_smart_rtl_failsafe_config task setup complete ==="