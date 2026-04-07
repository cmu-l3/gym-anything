#!/bin/bash
echo "=== Setting up esc_burn_in_jump_mission task ==="

source /workspace/scripts/task_utils.sh

# 1. Create working directory and remove any pre-existing output
mkdir -p /home/ga/Documents/QGC
rm -f /home/ga/Documents/QGC/burn_in.plan
chown -R ga:ga /home/ga/Documents/QGC

# 2. Write the engineering test specification document
cat > /home/ga/Documents/QGC/burn_in_spec.txt << 'SPECDOC'
ENGINEERING TEST SPECIFICATION — ESC/MOTOR BURN-IN
Vehicle: Agro-Hex Heavy (SITL Simulation)
Task: Powertrain Continuous Load Test
Date: 2026-03-10

=== OBJECTIVE ===
Perform a continuous flight load test on the newly installed Electronic Speed
Controllers (ESCs) and motors. The vehicle must fly a continuous loop at high
speed to sustain maximum current draw.

=== PART 1: FLIGHT DYNAMICS CONFIGURATION ===
The default navigation speed is too slow to stress the powertrain. 
Go to QGroundControl > Vehicle Setup (Q icon -> Vehicle Setup) > Parameters.
Search for the parameter:
  WPNAV_SPEED
Set this parameter to: 1200
(This configures the waypoint cruise speed to 1200 cm/s or 12 m/s).

=== PART 2: MISSION LOGIC CONFIGURATION ===
Instead of manually drawing hundreds of waypoints, use the DO_JUMP command
to repeat a short circuit. Go to QGC Plan View and build a mission with this
exact sequence:

1. Takeoff (Altitude ~20m)
2. Waypoint 1 (Start of circuit)
3. Waypoint 2
4. Waypoint 3
5. Waypoint 4 (End of circuit - arrange them roughly in a rectangle/polygon)
6. Jump to item (DO_JUMP)
   - Set "Item #" (Target) to point to the Item Number of Waypoint 1.
   - Set "Repeat" to 25 (This will execute the circuit 25 times).
7. Return to Launch (RTL)
   - This must be the final item, executing only after the jump repeats are exhausted.

Save the completed mission plan file to:
  /home/ga/Documents/QGC/burn_in.plan
SPECDOC

chown ga:ga /home/ga/Documents/QGC/burn_in_spec.txt

# 3. Reset WPNAV_SPEED to the factory default (500) so the agent MUST change it
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
        
        # Reset to ArduCopter default 500 cm/s
        master.mav.param_set_send(sysid, compid, b'WPNAV_SPEED', 500.0, mavutil.mavlink.MAV_PARAM_TYPE_REAL32)
        time.sleep(0.5)
        print("Parameter WPNAV_SPEED reset to default (500).")
    else:
        print("WARNING: Could not connect to SITL to reset parameters")
except Exception as e:
    print(f"WARNING: Parameter reset failed: {e}")
PYEOF

# 4. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time

# 5. Ensure SITL and QGroundControl are running
echo "--- Checking ArduPilot SITL ---"
ensure_sitl_running

echo "--- Checking QGroundControl ---"
ensure_qgc_running

# 6. Focus, maximize, and prep the UI
sleep 2
maximize_qgc
sleep 1
dismiss_dialogs

# 7. Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== esc_burn_in_jump_mission task setup complete ==="
echo "Specification: /home/ga/Documents/QGC/burn_in_spec.txt"
echo "Expected Output: /home/ga/Documents/QGC/burn_in.plan"