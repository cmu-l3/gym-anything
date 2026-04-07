#!/bin/bash
# Setup script for Object-Relational Logistics task
# Creates the source CSV file and ensures a clean database state

set -e

echo "=== Setting up Object-Relational Logistics Task ==="

source /workspace/scripts/task_utils.sh

# --- Verify Oracle is running ---
echo "Checking Oracle container..."
if ! sudo docker ps | grep -q "$ORACLE_CONTAINER"; then
    echo "ERROR: Oracle container not running!"
    exit 1
fi

# --- Create source CSV file ---
echo "Creating legacy_manifests.csv..."
cat > /home/ga/Desktop/legacy_manifests.csv << EOF
SHIPMENT_ID,DESTINATION,ITEM_NAME,QUANTITY,UNIT_WEIGHT_KG
1001,New York,Industrial Air Filter,10,0.50
1001,New York,Valve Assembly Type A,5,1.20
1002,London,Red Bricks Pallet,2,850.00
1003,Tokyo,LED Monitor 27in,50,4.50
1003,Tokyo,HDMI Cable 2m,50,0.15
1003,Tokyo,Wireless Mouse,50,0.12
1004,Berlin,Office Chair,20,12.50
1004,Berlin,Desk Lamp,20,1.50
1004,Berlin,Extension Cord,10,0.50
1004,Berlin,Monitor Stand,20,2.00
EOF

# Ensure ga user owns the file
chown ga:ga /home/ga/Desktop/legacy_manifests.csv
chmod 644 /home/ga/Desktop/legacy_manifests.csv

# --- Clean up previous artifacts ---
echo "Cleaning up database artifacts..."
oracle_query "
BEGIN
    BEGIN EXECUTE IMMEDIATE 'DROP VIEW V_MANIFEST_WEIGHTS'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TABLE SHIPMENT_OBJECTS PURGE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TYPE T_MANIFEST_TAB FORCE'; EXCEPTION WHEN OTHERS THEN NULL; END;
    BEGIN EXECUTE IMMEDIATE 'DROP TYPE T_MANIFEST_ITEM FORCE'; EXCEPTION WHEN OTHERS THEN NULL; END;
END;
/" "hr" > /dev/null 2>&1 || true

# --- Record Task Start ---
date +%s > /tmp/task_start_timestamp

# --- Initial Screenshot ---
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Source file created at: /home/ga/Desktop/legacy_manifests.csv"
echo "Database cleaned of previous types/tables."