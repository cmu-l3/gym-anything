#!/bin/bash
echo "=== Setting up link_diagnosis_to_patient task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt
echo "$(date '+%Y-%m-%d %H:%M:%S')" > /tmp/task_start_iso.txt

# ============================================================
# 1. Clean Environment
# ============================================================
# Kill any existing MedinTux instance
pkill -f "Manager.exe" 2>/dev/null || true
pkill -f "wine" 2>/dev/null || true
sleep 2

# Ensure MySQL is running
systemctl start mysql 2>/dev/null || service mysql start 2>/dev/null || true
sleep 2

# ============================================================
# 2. Prepare Patient Data (DUBOIS Marie)
# ============================================================
# Check if patient exists
EXISTING_GUID=$(get_patient_guid "DUBOIS" "Marie")

if [ -n "$EXISTING_GUID" ]; then
    echo "Patient DUBOIS Marie exists (GUID: $EXISTING_GUID). Cleaning up old diagnoses..."
    # Clean up any existing records for this patient to ensure a fresh state
    # We delete from relevant content tables in DrTuxTest linked to this GUID
    # Note: Schema is complex, but commonly Rubriques (notes) or Terrain (history) store this
    mysql -u root DrTuxTest -e "DELETE FROM Rubriques WHERE Rbq_IDDos='$EXISTING_GUID'" 2>/dev/null || true
    mysql -u root DrTuxTest -e "DELETE FROM RubriquesHead WHERE Rbq_IDDos='$EXISTING_GUID'" 2>/dev/null || true
else
    echo "Creating patient DUBOIS Marie..."
    # Generate a GUID usually looks like: {GUID-....} or just UUID
    GUID="DUBOIS-MARIE-$(date +%s)"
    
    # Insert using utility function
    # usage: insert_patient "GUID" "NOM" "Prenom" "YYYY-MM-DD" "H|F" "Titre" "Adresse" "CP" "Ville" "Tel" "NumSS"
    insert_patient "$GUID" "DUBOIS" "Marie" "1958-06-12" "F" "Mme" \
        "42 rue de la République" "69002" "Lyon" "04 72 11 22 33" "2580669002042"
        
    echo "Patient created with GUID: $GUID"
fi

# Remove the output file if it exists from previous run
rm -f /home/ga/diagnosis_result.txt 2>/dev/null || true

# ============================================================
# 3. Launch Application
# ============================================================
echo "Launching MedinTux..."
launch_medintux_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Task: Link diagnosis I10 (Hypertension) to patient DUBOIS Marie"