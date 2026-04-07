#!/bin/bash
set -euo pipefail

echo "=== Setting up jupiter_trojan_tadpole_analysis task ==="

source /workspace/scripts/task_utils.sh || { echo "Failed to source task_utils.sh"; exit 1; }

# Clean previous artifacts
echo "Cleaning workspace..."
rm -f /home/ga/Desktop/achilles_data.txt
rm -f /home/ga/GMAT_output/tadpole_mission.script
rm -f /home/ga/GMAT_output/tadpole_metrics.json
mkdir -p /home/ga/GMAT_output
chown -R ga:ga /home/ga/GMAT_output

# Record start time
date +%s > /tmp/task_start_time.txt

# Create initial data file
cat > /home/ga/Desktop/achilles_data.txt << 'EOF'
Target: 588 Achilles (L4 Trojan)
Epoch: 01 Jan 2025 12:00:00.000 UTC
Central Body: Sun
Reference Frame: SunMJ2000Eq

Keplerian Elements:
SMA = 778500000.0 km
ECC = 0.147
INC = 10.3 deg
RAAN = 316.5 deg
AOP = 133.2 deg
TA = 75.0 deg
EOF
chown ga:ga /home/ga/Desktop/achilles_data.txt

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