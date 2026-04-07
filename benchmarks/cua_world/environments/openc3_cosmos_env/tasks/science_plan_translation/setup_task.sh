#!/bin/bash
echo "=== Setting up Science Plan Translation task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Wait for COSMOS API to be ready
echo "Waiting for COSMOS API..."
if ! wait_for_cosmos_api 60; then
    echo "WARNING: COSMOS API not ready, continuing anyway"
fi

# Remove stale output files FIRST
rm -f /home/ga/Desktop/pass_summary.json 2>/dev/null || true
rm -f /home/ga/Desktop/run_observations.py 2>/dev/null || true
rm -f /tmp/science_plan_translation_result.json 2>/dev/null || true
rm -f /home/ga/Documents/observation_schedule.csv 2>/dev/null || true

# Generate the Science Plan CSV (Real-world formatted payload)
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/observation_schedule.csv << 'EOF'
observation_id,target_name,wait_sec,exposure_time
OBS-001,AlphaCentauri,1.0,2.5
OBS-002,Sirius,2.0,3.0
OBS-003,Betelgeuse,1.0,4.0
OBS-004,Rigel,1.0,5.5
OBS-005,Vega,2.0,1.5
OBS-006,Pleiades,1.0,6.0
OBS-007,AndromedaCore,1.0,2.0
OBS-008,OrionNebula,2.0,8.0
OBS-009,CrabPulsar,1.0,10.0
OBS-010,Jupiter,1.0,5.0
EOF
chown ga:ga /home/ga/Documents/observation_schedule.csv

# Record task start timestamp AFTER cleanup and generation
date +%s > /tmp/science_plan_translation_start_ts
echo "Task start recorded: $(cat /tmp/science_plan_translation_start_ts)"

# Record initial COLLECTS telemetry value (to verify the agent actually commanded the satellite)
INITIAL_COLLECTS=$(cosmos_tlm "INST HEALTH_STATUS COLLECTS" 2>/dev/null || echo "0")
echo "Initial COLLECTS: $INITIAL_COLLECTS"
printf '%s' "$INITIAL_COLLECTS" > /tmp/science_plan_translation_initial_collects

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENC3_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|openc3\|cosmos" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Navigate to COSMOS home
echo "Navigating to COSMOS home..."
navigate_to_url "$OPENC3_URL"
sleep 5

# Focus and maximize the Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/science_plan_translation_start.png

echo "=== Science Plan Translation Setup Complete ==="
echo ""
echo "Task: Translate observation_schedule.csv into a Python automation script."
echo "Command the system and output report to: /home/ga/Desktop/pass_summary.json"
echo ""