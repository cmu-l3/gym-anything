#!/bin/bash
echo "=== Setting up high_security_asset_audit_logging task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record SQL start time for precise action_log querying
snipeit_db_query "SELECT NOW()" | tr -d '\n' > /tmp/audit_task_start_sql.txt
date +%s > /tmp/audit_task_start.txt

echo "--- Injecting Aerospace & Defense assets and locations ---"

# 1. Create specific SCIF Locations
snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('SCIF Alpha', NOW(), NOW()) ON DUPLICATE KEY UPDATE name='SCIF Alpha';"
snipeit_db_query "INSERT INTO locations (name, created_at, updated_at) VALUES ('SCIF Bravo', NOW(), NOW()) ON DUPLICATE KEY UPDATE name='SCIF Bravo';"

LOC_ALPHA=$(snipeit_db_query "SELECT id FROM locations WHERE name='SCIF Alpha' LIMIT 1" | tr -d '[:space:]')
LOC_BRAVO=$(snipeit_db_query "SELECT id FROM locations WHERE name='SCIF Bravo' LIMIT 1" | tr -d '[:space:]')

# 2. Create high-security laptop model
snipeit_db_query "INSERT INTO models (name, created_at, updated_at) VALUES ('Dell Latitude 7420 Rugged', NOW(), NOW());"
MDL_RUGGED=$(snipeit_db_query "SELECT id FROM models WHERE name='Dell Latitude 7420 Rugged' ORDER BY id DESC LIMIT 1" | tr -d '[:space:]')

# 3. Get generic Deployed or Ready to Deploy status
STATUS_DEPLOYED=$(snipeit_db_query "SELECT id FROM status_labels WHERE type='deployable' ORDER BY id ASC LIMIT 1" | tr -d '[:space:]')

# 4. Clean up any existing targets, then inject the 5 target assets
for i in {1..5}; do
    TAG="SEC-LPT-0$i"
    snipeit_db_query "DELETE FROM assets WHERE asset_tag='$TAG';"
    snipeit_db_query "INSERT INTO assets (asset_tag, name, model_id, status_id, rtd_location_id, location_id, created_at, updated_at) 
                      VALUES ('$TAG', 'Classified Rugged Laptop 0$i', $MDL_RUGGED, $STATUS_DEPLOYED, $LOC_ALPHA, $LOC_ALPHA, NOW(), NOW());"
done

# Ensure the Lost/Stolen status exists
LOST_STOLEN_EXISTS=$(snipeit_db_query "SELECT COUNT(*) FROM status_labels WHERE name='Lost/Stolen'" | tr -d '[:space:]')
if [ "$LOST_STOLEN_EXISTS" -eq 0 ]; then
    snipeit_db_query "INSERT INTO status_labels (name, type, color, show_in_nav, created_at, updated_at) VALUES ('Lost/Stolen', 'archived', '#F44336', 1, NOW(), NOW());"
fi

echo "  SCIF Alpha ID: $LOC_ALPHA"
echo "  SCIF Bravo ID: $LOC_BRAVO"
echo "  Rugged Model ID: $MDL_RUGGED"
echo "  Deployed Status ID: $STATUS_DEPLOYED"

# 5. Ensure Firefox is running and navigated to the dashboard
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3

# 6. Take initial screenshot
take_screenshot /tmp/audit_task_initial.png

echo "=== high_security_asset_audit_logging setup complete ==="