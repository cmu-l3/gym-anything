#!/bin/bash
echo "=== Setting up export_results_to_geojson task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist
# We need Muncie.p04.hdf to exist for the agent to read
if [ ! -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    echo "Running simulation to generate results..."
    run_simulation_if_needed
else
    echo "Results file Muncie.p04.hdf already exists."
fi

# Ensure the file is readable by the agent
chmod 644 "$MUNCIE_DIR/Muncie.p04.hdf" 2>/dev/null || true

# 3. Setup output directory
mkdir -p /home/ga/Documents/hec_ras_results
# Remove any pre-existing output to ensure clean state
rm -f /home/ga/Documents/hec_ras_results/muncie_results.geojson
chown -R ga:ga /home/ga/Documents/hec_ras_results

# 4. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 5. Launch terminal in project directory
launch_terminal "$MUNCIE_DIR"

# 6. Type 'ls' to show files
type_in_terminal "ls -lh Muncie.p04.hdf"

# 7. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="