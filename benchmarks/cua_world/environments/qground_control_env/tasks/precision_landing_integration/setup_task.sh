#!/bin/bash
echo "=== Setting up precision_landing_integration task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write integration manual document
cat > /home/ga/Documents/QGC/integration_manual.txt << 'MANUALDOC'
HARDWARE INTEGRATION MANUAL
Module: Precision Landing & Rangefinder Integration
Target: ArduCopter AC-SITL
Date: 2026-03-10

=== OVERVIEW ===
This vehicle is being upgraded with an IR-Lock sensor for precision landing
on an automated refill pad. Precision landing requires an active, downward-facing
rangefinder to estimate altitude accurately during the final descent phase.

You must configure the following 7 parameters in QGroundControl. All current
values are at their factory defaults and are incorrect.

=== 1. RANGEFINDER CONFIGURATION ===
Search for "RNGFND1" in QGC Parameters.

  RNGFND1_TYPE = 20
  (Value 20 = Lightware I2C. The default is 0/Disabled)

  RNGFND1_MIN_CM = 20
  (Minimum reliable range in centimeters)

  RNGFND1_MAX_CM = 1500
  (Maximum reliable range: 15 meters = 1500 cm)

  RNGFND1_ORIENT = 25
  (Value 25 = Downward. Essential for altitude measurement)

=== 2. PRECISION LANDING CONFIGURATION ===
Search for "PLND" in QGC Parameters.

  PLND_ENABLED = 1
  (Value 1 = Enabled. Activates the precision landing logic)

  PLND_TYPE = 2
  (Value 2 = IR-Lock sensor backend)

=== 3. DESCENT SPEED CONFIGURATION ===
Search for "LAND_SPEED".

  LAND_SPEED = 10
  (Final landing descent speed in cm/s. The default is 50 cm/s, which is
   too fast for the tracking algorithm to center the vehicle. Reduce to 10.)

=== 4. BACKUP CONFIGURATION ===
Once all 7 live parameters are set and successfully saved to the vehicle:
1. In the Parameters screen, click the "Tools" button (top right area of the parameter list).
2. Select "Save to file".
3. Save the full parameter list exactly as:
   /home/ga/Documents/QGC/plnd_backup.params

The vehicle is grounded until the backup is completed.
MANUALDOC

chown ga:ga /home/ga/Documents/QGC/integration_manual.txt

# 3. Reset target parameters to defaults so do-nothing = 0 pts
python3 << 'PYEOF'
import time
try:
    from pymavlink import mavutil
    master = mavutil.mavlink_connection('tcp:localhost:5762', source_system=254, dialect='ardupilotmega')
    msg = master.recv_match(type='HEARTBEAT', blocking=True, timeout=20)
    if msg:
        sysid = msg.get_srcSystem()
        compid = msg.get_srcComponent()
        time.sleep(2)  # warm-up
        # Reset to known defaults that differ from required values
        defaults = {
            b'RNGFND1_TYPE': 0.0,
            b'RNGFND1_MIN_CM': 0.0,
            b'RNGFND1_MAX_CM': 0.0,
            b'RNGFND1_ORIENT': 0.0,
            b'PLND_ENABLED': 0.0,
            b'PLND_TYPE': 0.0,
            b'LAND_SPEED': 50.0,
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

# 4. Remove any pre-existing backup file
rm -f /home/ga/Documents/QGC/plnd_backup.params

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure SITL running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 7. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 8. Focus and maximize QGC
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 9. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== precision_landing_integration task setup complete ==="
echo "Manual: /home/ga/Documents/QGC/integration_manual.txt"
echo "Expected backup: /home/ga/Documents/QGC/plnd_backup.params"