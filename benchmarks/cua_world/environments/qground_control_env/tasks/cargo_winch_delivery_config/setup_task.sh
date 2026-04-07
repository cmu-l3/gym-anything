#!/bin/bash
echo "=== Setting up cargo_winch_delivery_config task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write operations brief for the agent to read
cat > /home/ga/Documents/QGC/winch_ops_brief.txt << 'OPDOC'
=== MEDICAL CARGO WINCH DELIVERY BRIEF ===
Operation: Emergency Anti-Venom Delivery
Site: Remote Ranger Station (Unlandable Canopy)
Date: 2026-06-12

VEHICLE COMMISSIONING (WINCH SETUP):
The vehicle's primary winch module is active, but outputs must be mapped.
Configure the following parameters in QGroundControl:
- WINCH_RATE_MAX = 2.5 (Maximum tether speed in m/s)
- SERVO9_FUNCTION = 46 (Assigns Main Out 9 to Winch)
- RC8_OPTION = 45 (Assigns RC channel 8 to manual Winch Control)

DELIVERY MISSION PLAN:
Create an automated mission to drop the payload without landing.
- Delivery Zone: Lat -35.36310, Lon 149.16420
- Transit Altitude: 35 meters AGL

Sequence:
1. Takeoff to 35m.
2. Navigate to Delivery Zone at 35m.
3. Lower the winch:
   Add a MAV_CMD_DO_WINCH command (Advanced Command ID 42600).
   - Param 1 (Winch Number): 0
   - Param 2 (Action): 1 (Length Control)
   - Param 3 (Release Length): 15 (meters)
   - Param 4 (Rate): 1 (m/s)
4. Wait for rangers to detach payload:
   Add a Delay command for 20 seconds.
5. Retract the winch:
   Add another MAV_CMD_DO_WINCH command.
   - Param 1 (Winch Number): 0
   - Param 2 (Action): 1 (Length Control)
   - Param 3 (Release Length): 0 (meters - fully retracted)
   - Param 4 (Rate): 2.5 (m/s)
6. Return to Launch (RTL).

Save the mission plan to: /home/ga/Documents/QGC/winch_delivery.plan
OPDOC

chown ga:ga /home/ga/Documents/QGC/winch_ops_brief.txt

# 3. Reset parameters to defaults to ensure agent must set them
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
        
        # Reset to invalid defaults so do-nothing fails
        defaults = {
            b'WINCH_RATE_MAX': 1.0,
            b'SERVO9_FUNCTION': 0.0,
            b'RC8_OPTION': 0.0,
        }
        for pname, pval in defaults.items():
            master.mav.param_set_send(sysid, compid, pname, pval,
                                      mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
            time.sleep(0.3)
        print("Parameters reset to factory defaults")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Remove any existing plan to avoid false positives
rm -f /home/ga/Documents/QGC/winch_delivery.plan

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

echo "=== cargo_winch_delivery_config task setup complete ==="
echo "Brief: /home/ga/Documents/QGC/winch_ops_brief.txt"