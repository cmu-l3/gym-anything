#!/bin/bash
set -e
echo "=== Setting up asset_maintenance_logging task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Verify required prerequisites exist
echo "--- Verifying assets exist ---"
for TAG in ASSET-0001 ASSET-0002 ASSET-0003 ASSET-0005; do
    COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE asset_tag='${TAG}' AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$COUNT" -eq 0 ]; then
        echo "  WARNING: ${TAG} not found."
    else
        echo "  Found ${TAG}"
    fi
done

echo "--- Verifying suppliers exist ---"
for SUPPLIER in "Acme Corp" "Dell" "Lenovo" "HP"; do
    COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM suppliers WHERE name='${SUPPLIER}' AND deleted_at IS NULL" | tr -d '[:space:]')
    if [ "$COUNT" -eq 0 ]; then
        echo "  WARNING: Supplier '${SUPPLIER}' not found"
    else
        echo "  Found supplier '${SUPPLIER}'"
    fi
done

# 2. Clear any stale maintenance records matching our scenario titles (idempotency setup)
echo "--- Clearing any previous task maintenance records ---"
snipeit_db_query "DELETE FROM asset_maintenances WHERE title LIKE '%Q1 2025%' OR title LIKE '%critical failure%' OR title LIKE '%radiology workstation%' OR title LIKE '%quarterly maintenance%'" 2>/dev/null || true

# 3. Record initial maintenance count
INITIAL_MAINT_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM asset_maintenances" | tr -d '[:space:]')
echo "$INITIAL_MAINT_COUNT" > /tmp/initial_maintenance_count.txt
echo "--- Initial maintenance record count: $INITIAL_MAINT_COUNT ---"

# 4. Ensure Firefox is open to the Snipe-IT dashboard
echo "--- Ensuring Firefox is open ---"
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/maintenances"
sleep 3
focus_firefox

# 5. Take initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="