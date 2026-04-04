#!/bin/bash
echo "=== Setting up load_sample_project task ==="

# Clean up leftover temp files from previous tasks
rm -f /tmp/initial_* /tmp/ground_truth_* /tmp/task_result.json /tmp/task_end.png 2>/dev/null || true

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Record initial state (QBlade v0.96 uses .wpa project files)
INITIAL_WPA=$(find /home/ga/Documents/projects -name "*.wpa" 2>/dev/null | wc -l)
echo "$INITIAL_WPA" > /tmp/initial_wpa_count

# Record available sample projects
SAMPLE_DIR=$(find /opt/qblade -name "sample projects" -type d 2>/dev/null | head -1)
if [ -z "$SAMPLE_DIR" ]; then
    SAMPLE_DIR=$(find /opt/qblade -iname "sampleprojects" -type d 2>/dev/null | head -1)
fi
if [ -n "$SAMPLE_DIR" ]; then
    SAMPLE_FILES=$(find "$SAMPLE_DIR" -name "*.wpa" 2>/dev/null | wc -l)
    echo "$SAMPLE_FILES" > /tmp/initial_sample_count
    echo "Sample projects available at: $SAMPLE_DIR ($SAMPLE_FILES files)"
    ls -la "$SAMPLE_DIR"/*.wpa 2>/dev/null || true
else
    echo "0" > /tmp/initial_sample_count
    echo "No sample projects directory found"
fi

# Remove previous expected output
rm -f /home/ga/Documents/projects/my_turbine.wpa 2>/dev/null || true

# Ensure NACA 0015 airfoil data is available for fallback path
if [ ! -f /home/ga/Documents/airfoils/naca0015.dat ]; then
    cp /workspace/data/airfoils/naca0015.dat /home/ga/Documents/airfoils/ 2>/dev/null || true
    chown ga:ga /home/ga/Documents/airfoils/naca0015.dat 2>/dev/null || true
fi

# Launch QBlade
echo "Launching QBlade..."
source /workspace/scripts/task_utils.sh
launch_qblade

# Wait for QBlade to start
sleep 8

echo "=== Task setup complete ==="
