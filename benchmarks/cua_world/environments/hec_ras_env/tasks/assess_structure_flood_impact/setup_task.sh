#!/bin/bash
echo "=== Setting up assess_structure_flood_impact task ==="

source /workspace/scripts/task_utils.sh

# 1. Restore clean Muncie project
restore_muncie_project

# 2. Ensure simulation results exist (Pre-run to ensure deterministic ground truth availability)
# The agent is asked to verify/run, but we ensure it's there so we can generate ground truth reliably
run_simulation_if_needed

# 3. Create the Critical Infrastructure Input File
# Muncie reach stations roughly range from 28000 (US) to 14000 (DS)
# We pick stations and FFE to ensure a mix of FLOODED and SAFE
INPUT_CSV="$MUNCIE_DIR/critical_infrastructure.csv"
cat > "$INPUT_CSV" << EOF
Facility_Name,River_Station,FFE_ft
Water_Treatment_Plant,20500.0,935.5
Power_Substation_A,18250.0,928.0
Emergency_Shelter_North,25100.0,945.0
Bridge_Control_House,16400.0,922.0
Riverside_Clinic,15200.0,920.0
EOF

chown ga:ga "$INPUT_CSV"

# 4. Clean previous results
RESULTS_DIR="/home/ga/Documents/hec_ras_results"
mkdir -p "$RESULTS_DIR"
rm -f "$RESULTS_DIR/structure_impact_assessment.csv"
chown -R ga:ga "$RESULTS_DIR"

# 5. Record start time
date +%s > /tmp/task_start_time.txt

# 6. Open terminal in project directory
echo "Opening terminal..."
launch_terminal "$MUNCIE_DIR"

# 7. Type `ls` to show the input file
type_in_terminal "ls -l critical_infrastructure.csv"

# 8. Take initial screenshot
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="