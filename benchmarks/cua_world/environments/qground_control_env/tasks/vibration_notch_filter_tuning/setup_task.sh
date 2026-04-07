#!/bin/bash
echo "=== Setting up vibration_notch_filter_tuning task ==="

source /workspace/scripts/task_utils.sh

# 1. Create output directory
mkdir -p /home/ga/Documents/QGC
chown ga:ga /home/ga/Documents/QGC

# 2. Write FFT analysis report
cat > /home/ga/Documents/QGC/fft_analysis_report.txt << 'FFTDOC'
ENGINEERING REPORT: FFT VIBRATION ANALYSIS
Vehicle: Custom 16L Ag Hexacopter (AC-SITL-008)
Date: 2026-03-10
Analyst: Flight Dynamics Team

=== FLIGHT TEST OBSERVATIONS ===
The vehicle exhibits severe frame resonance during hover, resulting in
significant Z-axis aliasing and motor temperature spikes.

=== FFT LOG RESULTS ===
Primary Resonance Peak (Center Frequency): 92 Hz
Hover Thrust (Throttle output at stable hover): 0.24

=== RECOMMENDATIONS FOR HARMONIC NOTCH FILTER ===
We recommend configuring the ArduPilot Harmonic Notch Filter as follows:
- Enable the filter.
- Set tracking mode to Throttle.
- Target the Primary Resonance Peak (92 Hz) as the Center Frequency.
- Set the Bandwidth to exactly half of the Center Frequency.
- Set the Reference Thrust to match the Hover Thrust (0.24).
- Apply a deep attenuation of 40 dB to suppress the massive 30-inch props.
- Enable post-filter batch logging (Option 2) for the next test flight.

Please calculate the bandwidth and configure the flight controller.
FFTDOC

chown ga:ga /home/ga/Documents/QGC/fft_analysis_report.txt

# Remove any pre-existing summary file
rm -f /home/ga/Documents/QGC/filter_summary.txt

# 3. Reset all target parameters to factory/disabled defaults
# This ensures do-nothing = 0 pts and the agent must actually change them.
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
            b'INS_HNTCH_ENABLE': 0.0,
            b'INS_HNTCH_MODE': 0.0,
            b'INS_HNTCH_FREQ': 80.0,
            b'INS_HNTCH_BW': 40.0,
            b'INS_HNTCH_REF': 0.20,
            b'INS_HNTCH_ATT': 15.0,
            b'INS_LOG_BAT_OPT': 0.0,
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

echo "=== vibration_notch_filter_tuning task setup complete ==="
echo "Report: /home/ga/Documents/QGC/fft_analysis_report.txt"