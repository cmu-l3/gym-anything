#!/bin/bash
set -e
echo "=== Setting up record_compliance_effectiveness task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------------
# 1. Seed Database with Required Compliance Data
# -----------------------------------------------------------------------------
echo "Seeding Compliance Data..."

# Create Compliance Package: ISO 27001:2013
docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
    "INSERT INTO compliance_packages (title, description, created, modified) \
     SELECT 'ISO 27001:2013', 'Information Security Management System Standard', NOW(), NOW() \
     WHERE NOT EXISTS (SELECT 1 FROM compliance_packages WHERE title='ISO 27001:2013');" 2>/dev/null

# Get Package ID
PKG_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT id FROM compliance_packages WHERE title='ISO 27001:2013' LIMIT 1;")

if [ -n "$PKG_ID" ]; then
    # Create Compliance Item: A.11.2.8
    docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
        "INSERT INTO compliance_package_items (compliance_package_id, name, description, created, modified) \
         SELECT $PKG_ID, 'A.11.2.8 Clear Desk and Clear Screen', 'The policy for clear desk and clear screen should be adopted.', NOW(), NOW() \
         WHERE NOT EXISTS (SELECT 1 FROM compliance_package_items WHERE compliance_package_id=$PKG_ID AND name='A.11.2.8 Clear Desk and Clear Screen');" 2>/dev/null
    
    # Get Item ID
    ITEM_ID=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
        "SELECT id FROM compliance_package_items WHERE compliance_package_id=$PKG_ID AND name='A.11.2.8 Clear Desk and Clear Screen' LIMIT 1;")
    
    # Create/Reset Compliance Analysis Record (Set to 'Not Tested' or 'Fail')
    # Assuming status 3 = Not Tested/Open, or creating a fresh record
    if [ -n "$ITEM_ID" ]; then
        # Check if analysis exists
        ANALYSIS_EXISTS=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
            "SELECT COUNT(*) FROM compliance_analysis WHERE compliance_package_item_id=$ITEM_ID;")
            
        if [ "$ANALYSIS_EXISTS" -eq "0" ]; then
            docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
                "INSERT INTO compliance_analysis (compliance_package_item_id, compliance_status, findings, created, modified) \
                 VALUES ($ITEM_ID, 3, 'Initial state - Not Tested', NOW(), NOW());" 2>/dev/null
            echo "Created new analysis record."
        else
            # Reset existing to clean state
            docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -e \
                "UPDATE compliance_analysis SET compliance_status=3, findings='Reset for task', next_review=NULL, modified=NOW() \
                 WHERE compliance_package_item_id=$ITEM_ID;" 2>/dev/null
            echo "Reset existing analysis record."
        fi
    fi
else
    echo "ERROR: Failed to create/find Compliance Package."
fi

# -----------------------------------------------------------------------------
# 2. Prepare Application State
# -----------------------------------------------------------------------------
echo "Launching Firefox..."
# Ensure Firefox is running and logged in (handled by env setup mostly, but we force url)
ensure_firefox_eramba "http://localhost:8080/compliance-analysis/index"

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

# Record initial count/state for verification
INITIAL_STATE=$(docker exec eramba-db mysql -u eramba -peramba_db_pass eramba -N -e \
    "SELECT compliance_status, findings, next_review FROM compliance_analysis \
     WHERE compliance_package_item_id IN (SELECT id FROM compliance_package_items WHERE name='A.11.2.8 Clear Desk and Clear Screen')" 2>/dev/null)
echo "Initial DB State: $INITIAL_STATE" > /tmp/initial_db_state.txt

echo "=== Setup complete ==="