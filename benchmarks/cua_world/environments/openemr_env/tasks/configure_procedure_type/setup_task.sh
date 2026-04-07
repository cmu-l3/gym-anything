#!/bin/bash
# Setup script for Configure Procedure Type Task

echo "=== Setting up Configure Procedure Type Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start timestamp (for anti-gaming)
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Check if HbA1c procedure already exists (should not exist)
echo "Checking for existing HbA1c procedure type..."
EXISTING_HBA1C=$(openemr_query "SELECT procedure_type_id, name, procedure_code FROM procedure_type WHERE name LIKE '%HbA1c%' OR name LIKE '%A1c%' OR name LIKE '%Hemoglobin A%' OR procedure_code = '83036'" 2>/dev/null)

if [ -n "$EXISTING_HBA1C" ]; then
    echo "WARNING: HbA1c procedure type already exists, removing for clean state..."
    echo "Existing records: $EXISTING_HBA1C"
    
    # Get all related IDs (parent and children)
    PROC_IDS=$(openemr_query "SELECT procedure_type_id FROM procedure_type WHERE name LIKE '%HbA1c%' OR name LIKE '%A1c%' OR name LIKE '%Hemoglobin A%' OR procedure_code = '83036'" 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    if [ -n "$PROC_IDS" ]; then
        # Delete child records first (results), then parent (orders)
        openemr_query "DELETE FROM procedure_type WHERE parent IN ($PROC_IDS)" 2>/dev/null || true
        openemr_query "DELETE FROM procedure_type WHERE procedure_type_id IN ($PROC_IDS)" 2>/dev/null || true
        echo "Cleaned up existing HbA1c procedure types"
    fi
fi

# Record initial max procedure_type_id for comparison
MAX_PROC_ID=$(openemr_query "SELECT COALESCE(MAX(procedure_type_id), 0) FROM procedure_type" 2>/dev/null || echo "0")
echo "$MAX_PROC_ID" > /tmp/initial_max_proc_id
echo "Initial max procedure_type_id: $MAX_PROC_ID"

# Record initial procedure type count
INITIAL_COUNT=$(openemr_query "SELECT COUNT(*) FROM procedure_type" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_proc_count
echo "Initial procedure type count: $INITIAL_COUNT"

# Verify the procedure_type table exists and has the expected structure
echo "Verifying procedure_type table structure..."
TABLE_CHECK=$(openemr_query "DESCRIBE procedure_type" 2>/dev/null | head -5)
if [ -z "$TABLE_CHECK" ]; then
    echo "WARNING: procedure_type table may not exist or is inaccessible"
else
    echo "procedure_type table verified"
fi

# Ensure Firefox is running on OpenEMR login page
echo "Ensuring Firefox is running..."
OPENEMR_URL="http://localhost/interface/login/login.php?site=default"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$OPENEMR_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 5
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|OpenEMR" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus and maximize Firefox window
echo "Focusing Firefox window..."
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "Initial screenshot saved"

echo ""
echo "=== Configure Procedure Type Task Setup Complete ==="
echo ""
echo "TASK: Add HbA1c Laboratory Procedure Type"
echo "=========================================="
echo ""
echo "Navigation Path:"
echo "  Administration > Other > Procedures > Configuration"
echo ""
echo "Required Information:"
echo "  - Procedure Name: HbA1c (or Hemoglobin A1c)"
echo "  - CPT Code: 83036"
echo "  - LOINC Code: 4548-4"
echo "  - Result Units: %"
echo "  - Normal Range: 4.0-5.6"
echo ""
echo "Login Credentials:"
echo "  Username: admin"
echo "  Password: pass"
echo ""