#!/bin/bash
echo "=== Setting up run_unsteady_simulation task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Record the initial state of the HDF file for verification
# We want to ensure the simulation output is NEW
if [ -f "$MUNCIE_DIR/Muncie.p04.hdf" ]; then
    INITIAL_SIZE=$(stat -c %s "$MUNCIE_DIR/Muncie.p04.hdf" 2>/dev/null || echo "0")
    INITIAL_MTIME=$(stat -c %Y "$MUNCIE_DIR/Muncie.p04.hdf" 2>/dev/null || echo "0")
    echo "Initial p04.hdf size: $INITIAL_SIZE"
    echo "Initial p04.hdf mtime: $INITIAL_MTIME"
    echo "$INITIAL_SIZE" > /tmp/initial_hdf_size.txt
    echo "$INITIAL_MTIME" > /tmp/initial_hdf_mtime.txt
fi

# Record start time
date +%s > /tmp/task_start_time.txt

# 3. List available files for the agent to see
echo ""
echo "Project files in Muncie directory:"
ls -la "$MUNCIE_DIR/"

echo ""
echo "Available HEC-RAS executables:"
ls -la /opt/hec-ras/bin/ 2>/dev/null || echo "  (not found)"

# 4. Open a terminal in the Muncie directory
echo "Opening terminal in project directory..."
launch_terminal "$MUNCIE_DIR"

# 5. Show project files and available executables in the terminal
type_in_terminal "echo '=== Muncie Project Files ===' && ls -lh Muncie.* && echo '' && echo '=== HEC-RAS Executables ===' && ls /opt/hec-ras/bin/"

# 6. Take initial screenshot
sleep 2
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="
echo "Terminal is open in the Muncie project directory."
echo "Task: Run the unsteady flow simulation using RasUnsteady."
