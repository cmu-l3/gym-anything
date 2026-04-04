#!/bin/bash
echo "=== Setting up turbine_performance_evaluation ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/Documents/projects"
SAMPLE_DIR="/home/ga/Documents/sample_projects"
mkdir -p "$PROJECT_DIR"

# Distinct starting state: no airfoil files in the airfoils directory
# (this task uses a complete pre-built sample project, not raw airfoils)
rm -f /home/ga/Documents/airfoils/*.dat /home/ga/Documents/airfoils/polar_*.txt

# Verify sample projects exist
SAMPLE_COUNT=$(ls "$SAMPLE_DIR"/*.wpa 2>/dev/null | wc -l)
echo "Found $SAMPLE_COUNT sample projects in $SAMPLE_DIR"

if [ "$SAMPLE_COUNT" -eq 0 ]; then
    # Try to find them from the QBlade installation
    for d in /opt/qblade/*/sample\ projects /opt/qblade/*/*/sample\ projects; do
        if [ -d "$d" ]; then
            cp "$d"/*.wpa "$SAMPLE_DIR/" 2>/dev/null
            echo "Copied sample projects from $d"
            break
        fi
    done
fi

# List available samples for debugging
echo "Available sample projects:"
ls -la "$SAMPLE_DIR"/*.wpa 2>/dev/null

# Record baseline
INITIAL_TXT_COUNT=$(ls "$PROJECT_DIR"/*.txt 2>/dev/null | wc -l)
echo "$INITIAL_TXT_COUNT" > /tmp/initial_txt_count

# Record hashes of sample projects for anti-copy check on .wpa files
SAMPLE_HASHES=""
for wpa in "$SAMPLE_DIR"/*.wpa; do
    if [ -f "$wpa" ]; then
        h=$(md5sum "$wpa" 2>/dev/null | cut -d' ' -f1)
        SAMPLE_HASHES="${SAMPLE_HASHES}${h}\n"
    fi
done
echo -e "$SAMPLE_HASHES" > /tmp/initial_sample_hashes

# Remove previous outputs
rm -f "$PROJECT_DIR/nrel5mw_bem_results.txt"
rm -f "$PROJECT_DIR/nrel5mw_report.txt"

# Record timestamp
date +%s > /tmp/task_start_timestamp

# Launch QBlade
launch_qblade
sleep 8
wait_for_qblade 30

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
