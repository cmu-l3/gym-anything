#!/bin/bash
set -e
echo "=== Setting up observatory_dome_sync_commissioning task ==="

source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming measure)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Documents/dome_commissioning_plan.txt
rm -f /home/ga/Documents/dome_sync_report.csv
rm -f /home/ga/Documents/dome_slaved_evidence.png
rm -f /tmp/task_result.json

mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Documents

# 3. Ensure base INDI simulators are running (dome is intentionally missing)
ensure_indi_running
sleep 2
connect_all_devices

# 4. Ensure KStars is running and maximized
ensure_kstars_running
sleep 3
maximize_kstars
focus_kstars
sleep 1

# 5. Put telescope in known safe parked state
indi_setprop "Telescope Simulator.TELESCOPE_PARK.PARK=On" 2>/dev/null || true

# 6. Create the commissioning plan document
cat > /home/ga/Documents/dome_commissioning_plan.txt << 'EOF'
OBSERVATORY COMMISSIONING DIRECTIVE
System: Dome Synchronization (Slaving)
Site: Siding Spring Observatory (Lat: -31.2722, Lon: 149.0661)

OBJECTIVE:
Verify that the new dome correctly slaves to the telescope mount and tracks azimuth changes accurately across the sky.

REQUIREMENTS:
1. Restart the INDI server to include the 'indi_simulator_dome' driver alongside the existing telescope/CCD/focuser/filter simulator devices.
2. Configure the Telescope Simulator with the Siding Spring site coordinates (Lat/Lon).
3. Connect the Dome Simulator and enable Dome Slaving so the dome automatically follows the telescope's azimuth.
4. Slew the telescope to the following three test targets in order:
   - Sirius (J2000: RA 06h 45m 09s, Dec -16° 42' 58")
   - Canopus (J2000: RA 06h 23m 57s, Dec -52° 41' 44")
   - Alpha Centauri (J2000: RA 14h 39m 36s, Dec -60° 50' 02")
5. Allow the telescope and dome to settle completely at each target.
6. Record the UTC time of settlement, the Telescope's Azimuth, and the Dome's Azimuth.

DELIVERABLES:
1. A CSV report at /home/ga/Documents/dome_sync_report.csv
   Format strictly as: Target,Timestamp_UTC,Telescope_Az,Dome_Az
   (Example Timestamp: 2026-03-10T02:15:30Z)
2. Visual evidence: Save a screenshot to /home/ga/Documents/dome_slaved_evidence.png showing the dome actively slaved (either the Ekos Dome tab, or the terminal running your custom slaving script).
EOF

chown ga:ga /home/ga/Documents/dome_commissioning_plan.txt
echo "Commissioning plan written to /home/ga/Documents/dome_commissioning_plan.txt"

# 7. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="