#!/bin/bash
echo "=== Setting up satcom_telemetry_bandwidth_reduction task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write communications brief document
cat > /home/ga/Documents/QGC/satcom_brief.txt << 'BRIEFDOC'
UAV COMMUNICATIONS BRIEF
Subject: SATCOM Link Bandwidth Reduction
Date: 2026-03-10

BACKGROUND:
This vehicle is being deployed for Beyond Visual Line of Sight (BVLOS) maritime operations. It will communicate with the ground station exclusively via an Iridium satellite modem connected to the flight controller's Serial 2 port. 

PROBLEM:
The Serial 2 telemetry stream rates (SR2_*) are currently at factory defaults (10 Hz). This will immediately saturate the 2400 baud satellite link, causing massive latency and control loss.

REQUIRED ACTIONS:
Navigate to Vehicle Setup > Parameters in QGroundControl. Search for "SR2_" and configure the following 8 parameters exactly as shown:

CRITICAL DATA (Throttle to 1 Hz):
  SR2_POSITION = 1
  SR2_EXT_STAT = 1
  SR2_EXTRA1   = 1
  SR2_EXTRA2   = 1

NON-CRITICAL DATA (Disable completely to save bandwidth):
  SR2_EXTRA3   = 0
  SR2_RAW_CTRL = 0
  SR2_RAW_SENS = 0
  SR2_RC_CHAN  = 0

EXPORT REQUIREMENT:
Once all 8 parameters are set and accepted by the vehicle, export the complete parameter set so we can deploy it to the other drones in the fleet.
Click the "Tools" button in the upper-right of the Parameters screen, select "Save to file...", and save the file to:
  /home/ga/Documents/QGC/satcom_link.params

Do NOT skip the export step. The task is incomplete without the saved .params file.
BRIEFDOC

chown ga:ga /home/ga/Documents/QGC/satcom_brief.txt

# 3. Reset target parameters to high bandwidth (10 Hz) so do-nothing = 0 pts
echo "--- Resetting SR2 parameters to high bandwidth via pymavlink ---"
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
        
        # Set all SR2 stream rates to 10 (high bandwidth)
        high_bw = {
            b'SR2_POSITION': 10.0,
            b'SR2_EXT_STAT': 10.0,
            b'SR2_EXTRA1': 10.0,
            b'SR2_EXTRA2': 10.0,
            b'SR2_EXTRA3': 10.0,
            b'SR2_RAW_CTRL': 10.0,
            b'SR2_RAW_SENS': 10.0,
            b'SR2_RC_CHAN': 10.0,
        }
        for pname, pval in high_bw.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to 10 Hz defaults.")
    else:
        print("WARNING: Could not connect to SITL to reset parameters.")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any pre-existing params file
rm -f /home/ga/Documents/QGC/satcom_link.params

# 5. Record task start time
date +%s > /tmp/task_start_time.txt

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

echo "=== satcom_telemetry_bandwidth_reduction task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/satcom_brief.txt"
echo "Expected export: /home/ga/Documents/QGC/satcom_link.params"