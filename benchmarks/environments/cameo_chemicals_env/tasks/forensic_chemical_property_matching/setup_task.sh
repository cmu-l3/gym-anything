#!/bin/bash
echo "=== Setting up Forensic Chemical Property Matching Task ==="

# Source utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents
mkdir -p /home/ga/Desktop

# Clean up any previous run artifacts
rm -f /home/ga/Documents/chemical_identification_report.txt

# Create the Lab Measurements file on the Desktop
# This gives the agent the input data in a file as well as the description
cat > /home/ga/Desktop/lab_measurements.txt << EOF
LABORATORY MEASUREMENTS - UNKNOWN BOTTLES
=========================================

CANDIDATE CHEMICALS LIST (Found Labels):
1. Acetonitrile
2. Cyclohexane
3. Tetrahydrofuran
4. Pyridine
5. Ethyl Acetate

MEASUREMENTS:
Bottle A: 
  - Boiling Point: ~82 deg C
  - Flash Point: ~2 deg C
  - Water Solubility: Miscible/Soluble

Bottle B: 
  - Boiling Point: ~66 deg C
  - Flash Point: ~-14 deg C
  - Water Solubility: Miscible

Bottle C: 
  - Boiling Point: ~115 deg C
  - Flash Point: ~20 deg C
  - Water Solubility: Soluble

Bottle D: 
  - Boiling Point: ~77 deg C
  - Flash Point: ~-4 deg C
  - Water Solubility: Soluble

Bottle E: 
  - Boiling Point: ~81 deg C
  - Flash Point: ~-20 deg C
  - Water Solubility: Insoluble (Floats on water)

INSTRUCTIONS:
Use CAMEO Chemicals (https://cameochemicals.noaa.gov/) to find the reference properties 
for the candidate chemicals and match them to the bottles above.
EOF

# Set ownership
chown ga:ga /home/ga/Desktop/lab_measurements.txt

# Launch Firefox to CAMEO Chemicals
echo "Launching Firefox..."
if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox -P default --no-remote 'https://cameochemicals.noaa.gov/' > /tmp/firefox.log 2>&1 &"
    
    # Wait for Firefox to start
    for i in {1..45}; do
        if pgrep -f firefox > /dev/null; then
            break
        fi
        sleep 1
    done
    sleep 5
fi

# Maximize Firefox window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Capture initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="