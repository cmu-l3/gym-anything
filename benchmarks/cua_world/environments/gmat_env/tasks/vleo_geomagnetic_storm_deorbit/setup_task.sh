#!/bin/bash
set -euo pipefail

echo "=== Setting up vleo_geomagnetic_storm_deorbit task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean workspace
rm -f /home/ga/Desktop/space_weather_brief_SL47.txt
rm -f /home/ga/GMAT_output/storm_decay_simulation.script
rm -f /home/ga/GMAT_output/storm_survival_report.txt
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time
date +%s > /tmp/task_start_time.txt

# Create ground truth / brief
cat > /home/ga/Desktop/space_weather_brief_SL47.txt << 'EOF'
================================================================
SPACE WEATHER ANOMALY ASSESSMENT
Event Reference: SL-Group-4-7 Geomagnetic Storm
Date: 04 Feb 2022
================================================================

SPACECRAFT PARAMETERS (High-Drag Configuration)
------------------------------------------------
Mass:           260.0 kg
Drag Area:      10.0 m^2  (Solar arrays unable to feather)
Cd:             2.2
Cr:             1.4
SRP Area:       10.0 m^2

INITIAL ORBIT STATE
------------------------------------------------
Coordinate System: EarthMJ2000Eq
Epoch:        03 Feb 2022 18:00:00.000 UTC
SMA:          6631.14 km  (approx 260 km altitude)
ECC:          0.0001
INC:          53.2 deg
RAAN:         0.0 deg
AOP:          0.0 deg
TA:           0.0 deg

ENVIRONMENTAL SCENARIOS
------------------------------------------------
Force Model Requirements for both: 
- Earth Gravity (JGM-2 or JGM-3, degree/order 8)
- Point Masses: Sun, Moon
- SRP: Enabled

1. NOMINAL CONDITIONS
Atmosphere Model: JacchiaRoberts
F10.7:            120
F10.7A:           120
Magnetic Index:   3   (Kp=3, Quiet to Unsettled)

2. STORM CONDITIONS
Atmosphere Model: JacchiaRoberts
F10.7:            140
F10.7A:           120
Magnetic Index:   8   (Kp=8, Severe Geomagnetic Storm)

ANALYSIS REQUIREMENTS
------------------------------------------------
Propagate both scenarios until Altitude < 120 km.
Maximum simulation time: 15 days.
EOF
chown ga:ga /home/ga/Desktop/space_weather_brief_SL47.txt

# Launch GMAT
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