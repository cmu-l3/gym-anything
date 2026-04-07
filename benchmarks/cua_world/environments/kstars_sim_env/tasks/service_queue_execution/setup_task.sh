#!/bin/bash
set -e
echo "=== Setting up service_queue_execution task ==="

source /workspace/scripts/task_utils.sh

# Record task start
date +%s > /tmp/task_start_time.txt

# Clean up any potential artifacts
rm -rf /home/ga/Images/queue
rm -f /home/ga/Documents/observing_queue.txt
rm -f /home/ga/Documents/session_log.txt
rm -f /tmp/task_result.json

# Create target directories
mkdir -p /home/ga/Images/queue/{m44,ngc2392,m51}
mkdir -p /home/ga/Documents
chown -R ga:ga /home/ga/Images/queue
chown -R ga:ga /home/ga/Documents

# Connect devices and configure INDI
ensure_indi_running
sleep 2
connect_all_devices

indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_1=Luminance" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_2=V" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_3=B" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_4=R" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_5=Ha" 2>/dev/null || true
indi_setprop "Filter Wheel Simulator.FILTER_NAME.FILTER_SLOT_NAME_6=OIII" 2>/dev/null || true
sleep 1

# Slew to Polaris (wrong target entirely)
unpark_telescope
sleep 1
slew_to_coordinates 2.5 89.0
wait_for_slew_complete 20
echo "Telescope is deliberately parked at Polaris. Agent must slew to targets."

# Neutral CCD configuration
set_ccd_upload_dir "/home/ga/Images/captures"
indi_setprop "CCD Simulator.CCD_FRAME_TYPE.FRAME_LIGHT=On" 2>/dev/null || true

# Write queue document
cat > /home/ga/Documents/observing_queue.txt << 'EOF'
================================================================
  SERVICE OBSERVING QUEUE — Night of 2024-11-15
  Observatory: Simulated 200mm f/3.75 Reflector
  Operator: Execute all programs in queue order.
================================================================

QUEUE ENTRY 1 — PRIORITY: HIGH
  PI: Dr. L. Chen (Proposal 2024B-0142)
  Target: M44 (Beehive Cluster / Praesepe)
  Coordinates: RA 08h 40m 24s, Dec +19° 40' 00"
  Filters: B (slot 3) and V (slot 2)
  Exposures: 5 per filter, 30 seconds each
  Frame type: LIGHT
  Upload to: /home/ga/Images/queue/m44/
  Science goal: BV photometry for open cluster CMD study

QUEUE ENTRY 2 — PRIORITY: MEDIUM
  PI: Dr. R. Vasquez (Proposal 2024B-0287)
  Target: NGC 2392 (Eskimo Nebula)
  Coordinates: RA 07h 29m 10.8s, Dec +20° 54' 42"
  Filters: Ha (slot 5) and OIII (slot 6)
  Exposures: 3 per filter, 60 seconds each
  Frame type: LIGHT
  Upload to: /home/ga/Images/queue/ngc2392/
  Science goal: Narrowband emission survey of planetary nebulae

QUEUE ENTRY 3 — PRIORITY: MEDIUM
  PI: Dr. A. Okonkwo (Proposal 2024B-0391)
  Target: M51 (Whirlpool Galaxy)
  Coordinates: RA 13h 29m 52.7s, Dec +47° 11' 43"
  Filters: Luminance (slot 1) and R (slot 4)
  Exposures: 4 per filter, 120 seconds each
  Frame type: LIGHT
  Upload to: /home/ga/Images/queue/m51/
  Science goal: Deep imaging for tidal feature morphology

================================================================
SESSION LOG REQUIREMENTS
  For each target, record:
    - Target name and coordinates used
    - Filters and number of exposures completed
    - Any issues encountered
  Save to: /home/ga/Documents/session_log.txt
================================================================
EOF

chown ga:ga /home/ga/Documents/observing_queue.txt

# Start and focus KStars
ensure_kstars_running
sleep 3
for i in 1 2; do DISPLAY=:1 xdotool key Escape 2>/dev/null || true; sleep 1; done
maximize_kstars
focus_kstars
sleep 1

# Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="