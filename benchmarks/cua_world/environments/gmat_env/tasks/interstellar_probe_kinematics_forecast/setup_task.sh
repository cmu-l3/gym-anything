#!/bin/bash
set -euo pipefail

echo "=== Setting up interstellar_probe_kinematics_forecast task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# 1. Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/probe_ephemeris_2025.txt
rm -f /home/ga/Documents/missions/interstellar_forecast.script
rm -rf /home/ga/GMAT_output
mkdir -p /home/ga/Documents/missions
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/Documents/missions
chown -R ga:ga /home/ga/GMAT_output

# 2. Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the ephemeris data file on Desktop
cat > /home/ga/Desktop/probe_ephemeris_2025.txt << 'EPH_EOF'
=== ACTIVE INTERSTELLAR PROBES - EPHEMERIS DATA ===
Source: JPL Horizons
Coordinate System: Sun-Centered Equatorial (SunMJ2000Eq)
Epoch: 01 Jan 2025 12:00:00.000 UTC

--- VOYAGER 1 ---
X  : -6.643609806650E+09 km
Y  : -2.316885664871E+10 km
Z  :  5.672809187372E+09 km
VX :  1.127815234237E+01 km/s
VY :  1.050516766635E+01 km/s
VZ :  7.158097746404E+00 km/s

--- VOYAGER 2 ---
X  :  1.636605052917E+10 km
Y  : -1.096773539744E+10 km
Z  : -8.966453110908E+09 km
VX : -1.306057850550E+01 km/s
VY :  6.252654316035E+00 km/s
VZ :  4.819779344211E+00 km/s

--- NEW HORIZONS ---
X  :  2.871033660377E+09 km
Y  : -8.540131102941E+09 km
Z  :  4.568469956427E+08 km
VX :  6.136009859580E+00 km/s
VY : -1.246479708688E+01 km/s
VZ : -2.433296683505E+00 km/s
EPH_EOF

chown ga:ga /home/ga/Desktop/probe_ephemeris_2025.txt

# 4. Launch GMAT
echo "Launching GMAT..."
launch_gmat ""

echo "Waiting for GMAT window..."
WID=$(wait_for_gmat_window 60)

if [ -n "$WID" ]; then
    echo "GMAT window found: $WID"
    sleep 5
    dismiss_gmat_dialogs
    focus_gmat_window
    take_screenshot /tmp/task_initial_state.png
    echo "Initial screenshot captured."
else
    echo "ERROR: GMAT failed to start within timeout."
    exit 1
fi

echo "=== Task Setup Complete ==="