#!/bin/bash
set -e
echo "=== Setting up Task: Generate Model Configuration Report ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

PROJECT_DIR="/home/ga/Documents/hec_ras_projects/Muncie"
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
mkdir -p "$PROJECT_DIR"

# --- 1. Restore/Setup Muncie Project ---
echo "Restoring Muncie project..."
if [ -d "/opt/hec-ras/examples/Muncie" ]; then
    rm -rf "$PROJECT_DIR"/*
    cp -r /opt/hec-ras/examples/Muncie/* "$PROJECT_DIR/"
    chown -R ga:ga "$PROJECT_DIR"
else
    echo "ERROR: Muncie example not found in /opt/hec-ras/examples"
    exit 1
fi

# --- 2. Randomize Simulation Parameters ---
# We inject specific values into the .p04 file to ensure the agent parses
# the actual file and doesn't just hardcode defaults.

echo "Injecting random configuration values..."

# Generate random dates
YEAR=$((2023 + RANDOM % 5))
START_DAY=$((10 + RANDOM % 15))
END_DAY=$((START_DAY + 2))
MONTHS=("JAN" "FEB" "MAR" "APR" "MAY" "JUN" "JUL" "AUG")
MONTH=${MONTHS[$((RANDOM % 8))]}

START_DATE="${START_DAY}${MONTH}${YEAR}"
END_DATE="${END_DAY}${MONTH}${YEAR}"
START_TIME="0000"
END_TIME="1200"

# Select random computation interval
INTERVALS=("1MIN" "2MIN" "5MIN" "10MIN" "30SEC" "1HOUR")
COMP_INTERVAL=${INTERVALS[$((RANDOM % 6))]}

# Select random Plan Title
TITLES=("Unsteady Calibration Run A" "Proposed Conditions 2025" "Verification Run B" "Flood Study Update 4" "Base Scenario X")
PLAN_TITLE=${TITLES[$((RANDOM % 5))]}

# --- 3. Modify Muncie.p04 (Plan File) ---
# HEC-RAS Plan files use "Key=Value" syntax.
cd "$PROJECT_DIR"
P04_FILE=$(ls *.p04 | head -1)

if [ -z "$P04_FILE" ]; then
    echo "ERROR: No .p04 file found in $PROJECT_DIR"
    exit 1
fi

echo "Modifying $P04_FILE..."

# Replace Plan Title (handling spaces in replacement string)
sed -i "s/^Plan Title=.*/Plan Title=${PLAN_TITLE}/" "$P04_FILE"

# Replace Simulation Date
# Format: Simulation Date=01JAN2000,2400,02JAN2000,2400
NEW_DATE_LINE="Simulation Date=${START_DATE},${START_TIME},${END_DATE},${END_TIME}"
sed -i "s/^Simulation Date=.*/${NEW_DATE_LINE}/" "$P04_FILE"

# Replace Computation Interval
sed -i "s/^Computation Interval=.*/Computation Interval=${COMP_INTERVAL}/" "$P04_FILE"

# Ensure permissions are correct after modification
chown ga:ga "$P04_FILE"

# --- 4. Save Ground Truth for Verifier ---
# We save this to a hidden file in /tmp so the export script can pick it up
# but the agent is unlikely to find it easily.
cat > /tmp/.ground_truth.json << EOF
{
  "project_title": "Muncie Example Project",
  "plan_title": "${PLAN_TITLE}",
  "simulation_start_date": "${START_DATE}",
  "simulation_end_date": "${END_DATE}",
  "computation_interval": "${COMP_INTERVAL}",
  "geometry_file_extension": "g04"
}
EOF
chmod 644 /tmp/.ground_truth.json

echo "Setup complete. Target values:"
echo "  Date: $START_DATE to $END_DATE"
echo "  Interval: $COMP_INTERVAL"
echo "  Title: $PLAN_TITLE"

# --- 5. Prepare Environment ---
# Record start time
date +%s > /tmp/task_start_time.txt

# Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$PROJECT_DIR"

# Wait for terminal to be ready
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task Setup Complete ==="