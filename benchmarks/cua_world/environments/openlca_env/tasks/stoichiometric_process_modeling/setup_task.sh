#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Stoichiometric Process Modeling task ==="

# 1. Clean up previous results
rm -f /home/ga/LCA_Results/stoichiometry_check.txt 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
mkdir -p /home/ga/LCA_Results
chown ga:ga /home/ga/LCA_Results

# 2. Ensure USLCI database exists and is populated
# The task requires the agent to work IN the database, so we must ensure it exists.
echo "Checking for USLCI database..."
USLCI_DB=$(ensure_uslci_database)

if [ -z "$USLCI_DB" ]; then
    echo "USLCI database not found. Creating and importing..."
    
    # Create DB directory
    DB_DIR="/home/ga/openLCA-data-1.4/databases/USLCI_Stoich_Task"
    mkdir -p "$DB_DIR"
    chown -R ga:ga "$DB_DIR"
    
    # We can't easily perform a full import via CLI without a complex java runner.
    # However, if the environment is set up correctly, the agent might need to import it.
    # BUT, the task description says "The USLCI database is imported and active."
    # To be safe for the agent, we should try to pre-seed it if possible, 
    # OR we rely on the agent doing it if it's missing (but that changes task difficulty).
    # Given the environment scripts, we will check if we can copy a pre-made one 
    # or just let the user know they need to select it.
    
    # For this specific task, let's assume the standard 'USLCI_Analysis' or similar exists
    # from previous runs or we rely on the agent to import if missing. 
    # To be robust: We will attempt to unzip the JSON-LD to a staging area so it's ready.
    if [ -f "/opt/openlca_data/uslci_database.zip" ]; then
        cp /opt/openlca_data/uslci_database.zip /home/ga/LCA_Imports/
        chown ga:ga /home/ga/LCA_Imports/uslci_database.zip
    fi
    
    echo "NOTE: If no database is open, the agent may need to import USLCI first."
else
    echo "Database found at: $USLCI_DB"
    
    # 3. Clean up the specific process if it already exists (to prevent previous run contamination)
    # We query the DB to find the ID of "Quicklime Production, stoichiometric" and delete it?
    # Deleting via raw SQL in Derby is risky due to dependencies. 
    # Instead, we will count on the verifier checking the *latest* created process or checking timestamps.
    # But strictly, we can't easily delete via SQL without breaking references.
    # We will assume a "clean" run or that the agent deletes it if they see a conflict.
    # Or, we can rename the task requirement slightly if needed. 
    # For now, we leave existing DB alone to avoid corruption.
fi

# 4. Launch OpenLCA
echo "Launching OpenLCA..."
launch_openlca 300

# 5. Maximize window
WID=$(get_openlca_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    focus_window "$WID"
fi

# 6. Record start time
date +%s > /tmp/task_start_time.txt

# 7. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="