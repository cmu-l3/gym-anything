#!/bin/bash
echo "=== Setting up battery_nav_spray_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create directory for documents
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write the Standard Operating Procedure (SOP) document
cat > /home/ga/Documents/QGC/battery_nav_sop.txt << 'SOPDOC'
╔══════════════════════════════════════════════════════════════════╗
║  FLEET STANDARD OPERATING PROCEDURE — SPRAY DRONE COMMISSIONING  ║
║  Document: SOP-BAT-NAV-2024-Rev3                                 ║
║  Applies to: All 6S heavy-lift spray platforms                   ║
╚══════════════════════════════════════════════════════════════════╝

SECTION A: BATTERY MONITORING CONFIGURATION
============================================

Battery Specification:
  - Chemistry: LiPo 6S (22.2V nominal)
  - Capacity: 5200 mAh
  - Cell count: 6

Set the following parameters in QGroundControl (Vehicle Setup > Parameters):

  BATT_CAPACITY    = 5200     [mAh — must match pack capacity]
  BATT_LOW_VOLT    = 21.6     [V — low threshold: 3.6V per cell × 6]
  BATT_CRT_VOLT    = 20.4     [V — critical threshold: 3.4V per cell × 6]
  BATT_FS_LOW_ACT  = 2        [Action on low battery: RTL]
  BATT_FS_CRT_ACT  = 1        [Action on critical battery: Land]
  BATT_LOW_MAH     = 1040     [mAh remaining — 20% of 5200]
  BATT_CRT_MAH     = 520      [mAh remaining — 10% of 5200]

IMPORTANT: Factory defaults leave all voltage/mAh thresholds at 0
(disabled). Flying with disabled failsafes is a TERMINATION OFFENSE.


SECTION B: NAVIGATION SPEED CONFIGURATION
============================================

Spray drones carry heavy liquid payloads (10–16 kg). Reduced speeds
are MANDATORY for:
  (a) Uniform spray coverage at target application rate
  (b) Motor headroom for attitude corrections under load
  (c) Safe descent with heavy CG shift as tank empties

Set the following parameters:

  WPNAV_SPEED      = 350      [cm/s — cruise speed 3.5 m/s]
  WPNAV_SPEED_DN   = 100      [cm/s — descent speed 1.0 m/s]
  WPNAV_LOIT_SPEED = 250      [cm/s — loiter speed 2.5 m/s]

NOTE: ArduPilot stores all speeds in cm/s. Do NOT enter m/s values.


SECTION C: VERIFICATION
========================

After setting all 10 parameters, visually confirm each value in the
Parameters list. The vehicle will use the new values immediately —
no reboot required.

                    — END OF SOP DOCUMENT —
SOPDOC

chown ga:ga /home/ga/Documents/QGC/battery_nav_sop.txt

# 3. Ensure SITL is running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

# 4. Reset target parameters to defaults to ensure the agent must change them
echo "--- Resetting target parameters to defaults ---"
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
        
        # Factory defaults that deliberately differ from the SOP
        defaults = {
            b'BATT_CAPACITY': 3300.0,
            b'BATT_LOW_VOLT': 0.0,
            b'BATT_CRT_VOLT': 0.0,
            b'BATT_FS_LOW_ACT': 0.0,
            b'BATT_FS_CRT_ACT': 0.0,
            b'BATT_LOW_MAH': 0.0,
            b'BATT_CRT_MAH': 0.0,
            b'WPNAV_SPEED': 500.0,
            b'WPNAV_SPEED_DN': 150.0,
            b'WPNAV_LOIT_SPEED': 500.0
        }
        
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters successfully reset to defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 5. Record task start time
date +%s > /tmp/task_start_time

# 6. Ensure QGC running
echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 7. Focus, maximize, dismiss popups
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 8. Initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== battery_nav_spray_config task setup complete ==="
echo "SOP Document: /home/ga/Documents/QGC/battery_nav_sop.txt"