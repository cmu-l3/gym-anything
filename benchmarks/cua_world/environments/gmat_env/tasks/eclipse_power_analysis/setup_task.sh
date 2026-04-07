#!/bin/bash
set -euo pipefail

echo "=== Setting up eclipse_power_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/skywatch3_power_spec.txt
rm -f /home/ga/GMAT_output/skywatch3_eclipse.script
rm -f /home/ga/GMAT_output/eclipse_analysis_report.txt
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time
date +%s > /tmp/task_start_time.txt

# Create spec document (Real-world scenario)
cat > /home/ga/Desktop/skywatch3_power_spec.txt << 'SPECEOF'
================================================================
 SKYWATCH-3 EARTH OBSERVATION SATELLITE
 Power Subsystem Sizing — Orbital Eclipse Analysis Request
 Document: SW3-PWR-REQ-004  Rev B   Date: 2025-02-10
================================================================

1. MISSION ORBIT (as delivered by Launch Services)

   Orbit Type:         Sun-Synchronous
   Epoch:              01 Apr 2025 12:00:00.000 UTCG
   Semi-Major Axis:    6878.14 km   (altitude ~507 km)
   Eccentricity:       0.00115
   Inclination:        97.42 deg
   RAAN:               195.0 deg
   Argument of Perigee: 90.0 deg
   True Anomaly:       0.0 deg
   Coordinate System:  EarthMJ2000Eq

2. SPACECRAFT BUS

   Dry Mass:           165 kg
   Drag Coefficient:   2.2
   Drag Area:          1.8 m^2
   SRP Coefficient:    1.8
   SRP Area:           6.2 m^2

3. POWER SUBSYSTEM REQUIREMENTS

   Bus Power (eclipse, keep-alive + thermal): 285 W
   Battery Type:       Li-Ion (3.7V nominal)
   Battery Capacity:   20 Ah at 28.8 V bus = 576 Wh nameplate
   Depth of Discharge Limit:  40%  (usable: 230.4 Wh)
   Minimum Required Margin:   10%

   QUESTION: Is the usable battery energy (230.4 Wh) sufficient to
   sustain 285 W bus load through the WORST-CASE eclipse duration
   with >= 10% energy margin?

   Decision rule:
     Required_Wh = Bus_Power_W * Max_Eclipse_min / 60
     Margin = (Usable_Wh - Required_Wh) / Usable_Wh * 100%
     If Margin >= 10%  ->  BATTERY ADEQUATE
     If Margin < 10%   ->  BATTERY INADEQUATE

4. ANALYSIS REQUEST

   Propagate for 30 days from epoch. Use Earth as occulting body.
   Report the following in ~/GMAT_output/eclipse_analysis_report.txt:

     num_eclipses:          total count of umbra events
     max_eclipse_min:       longest eclipse duration in minutes
     avg_eclipse_min:       average eclipse duration in minutes
     eclipse_fraction:      fraction of total time in eclipse
     required_Wh:           energy needed for worst-case eclipse
     margin_percent:        energy margin percentage
     battery_adequate:      YES or NO

================================================================
SPECEOF

chown ga:ga /home/ga/Desktop/skywatch3_power_spec.txt

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