#!/bin/bash
set -e
echo "=== Setting up compute_courant_stability task ==="

source /workspace/scripts/task_utils.sh

# 1. Setup Environment
# Ensure directories exist
mkdir -p /home/ga/Documents/hec_ras_results
mkdir -p /home/ga/Documents/analysis_scripts
chown -R ga:ga /home/ga/Documents/hec_ras_results
chown -R ga:ga /home/ga/Documents/analysis_scripts

# 2. Restore Muncie Project
restore_muncie_project

# 3. Ensure Simulation Results Exist
# The agent needs the HDF5 file to analyze. We run it now if it's missing.
if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
    echo "Running HEC-RAS simulation to generate results..."
    
    # We need to run RasUnsteady. 
    # Muncie.p04.tmp.hdf is the unsteady output.
    # Arguments: ProjectName PlanName
    # Actually, RasUnsteady takes specific args. Let's try the standard run command.
    
    cd "$MUNCIE_DIR"
    # Ensure permissions
    chown -R ga:ga "$MUNCIE_DIR"
    
    # Create a dummy run script to ensure it runs correctly as user
    cat > /tmp/run_sim.sh << EOF
source /etc/profile.d/hec-ras.sh
cd "$MUNCIE_DIR"
# Run geometry preprocessor first just in case
RasGeomPreprocess Muncie.p04.tmp.hdf x04
# Run Unsteady
RasUnsteady Muncie.p04.tmp.hdf x04
EOF
    chmod +x /tmp/run_sim.sh
    su - ga -c "/tmp/run_sim.sh" > /tmp/sim_setup.log 2>&1
    
    if [ ! -f "$MUNCIE_DIR/Muncie.p04.tmp.hdf" ]; then
        echo "ERROR: Simulation failed to produce HDF file."
        cat /tmp/sim_setup.log
        # Fallback: copy a pre-baked HDF if we had one (we don't in this env)
        # But Muncie usually ships with results in some versions.
        # If failure, task is impossible.
    else
        echo "Simulation complete. Results generated."
    fi
else
    echo "Results file already exists."
fi

# 4. Anti-gaming: Record timestamps
date +%s > /tmp/task_start_time.txt
# Record the mtime of the HDF file so we know it wasn't modified by the agent (optional check)
stat -c %Y "$MUNCIE_DIR/Muncie.p04.tmp.hdf" > /tmp/hdf_initial_mtime.txt

# 5. Launch Terminal for the agent
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 6. Capture Initial State
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="