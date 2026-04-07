#!/bin/bash
echo "=== Setting up parachute_recovery_setup task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write PRS integration manual
cat > /home/ga/Documents/QGC/prs_integration_manual.txt << 'MANDOC'
PARACHUTE RECOVERY SYSTEM (PRS) INTEGRATION MANUAL
Vehicle: ArduCopter Hexacopter (Urban Config)
Standard: ASTM F3322
Date: 2026-03-10

=== OVERVIEW ===
To fly over populated areas, the vehicle must be equipped with an automated parachute system. If a motor failure or fly-away occurs, the flight controller will automatically stop the motors and deploy the parachute to ensure a safe descent rate.

=== PARAMETERS TO CONFIGURE ===
Use QGroundControl's Vehicle Setup > Parameters menu to configure the following settings.
Search for the prefix "CHUTE_" to find them easily.

1. CHUTE_ENABLED
   Set to: 1
   Description: Enables the parachute subsystem globally.

2. CHUTE_ALT_MIN
   Set to: 25
   Description: Minimum altitude (in meters) for auto-deployment. The parachute needs at least 25m to fully inflate.

3. CHUTE_CRT_SINK
   Set to: 4.5
   Description: Critical sink rate threshold (in m/s). If the vehicle falls faster than this, the parachute deploys.

4. CHUTE_DELAY_MS
   Set to: 250
   Description: Delay (in milliseconds) between shutting off the motors and ejecting the parachute to prevent lines from tangling in spinning props.

5. CHUTE_CHAN
   Set to: 8
   Description: Maps RC Channel 8 to a manual pilot override switch for emergency manual deployment.

=== COMPLIANCE REPORTING ===
After setting all 5 parameters, you must create a compliance sign-off report at:
/home/ga/Documents/QGC/prs_signoff.txt

The report MUST include:
- Confirmation that the PRS is Enabled
- The minimum deployment altitude (25m)
- The critical sink rate (4.5m/s)
- The assigned manual trigger channel (8)
- A formal statement declaring the vehicle "Airworthy"
MANDOC

chown ga:ga /home/ga/Documents/QGC/prs_integration_manual.txt

# 3. Reset target parameters to defaults (0) so do-nothing = 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # let MAVLink channel stabilize
        # Reset to known defaults (disabled/0)
        defaults = {
            b'CHUTE_ENABLED': 0.0,
            b'CHUTE_ALT_MIN': 10.0,
            b'CHUTE_CRT_SINK': 0.0,
            b'CHUTE_DELAY_MS': 0.0,
            b'CHUTE_CHAN': 0.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parachute parameters reset to defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing signoff report
rm -f /home/ga/Documents/QGC/prs_signoff.txt

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL and QGC running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus and maximize
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== parachute_recovery_setup task setup complete ==="