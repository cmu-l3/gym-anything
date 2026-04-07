#!/bin/bash
set -e
echo "=== Setting up create_vendor_invoice task ==="
source /workspace/scripts/task_utils.sh

# 1. Record task start time (epoch)
date +%s > /tmp/task_start_time.txt

# 2. Record initial AP invoice count for verification baseline
# issotrx='N' denotes AP (Purchase) side
CLIENT_ID=$(get_gardenworld_client_id)
INITIAL_COUNT=$(idempiere_query "SELECT COUNT(*) FROM c_invoice WHERE issotrx='N' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_ap_invoice_count.txt
echo "Initial AP invoice count: $INITIAL_COUNT"

# 3. Verify data prerequisites
echo "--- Verifying prerequisites ---"
# Check Vendor
VENDOR_CHECK=$(idempiere_query "SELECT count(*) FROM c_bpartner WHERE name='Seed Farm Inc.' AND isvendor='Y' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
if [ "$VENDOR_CHECK" -eq 0 ]; then
    echo "WARNING: Vendor 'Seed Farm Inc.' not found!"
else
    echo "Vendor 'Seed Farm Inc.' exists."
fi

# Check Products
for PROD in "Azalea Bush" "Oak Tree"; do
    PROD_CHECK=$(idempiere_query "SELECT count(*) FROM m_product WHERE name='$PROD' AND ad_client_id=$CLIENT_ID" 2>/dev/null || echo "0")
    if [ "$PROD_CHECK" -eq 0 ]; then
        echo "WARNING: Product '$PROD' not found!"
    else
        echo "Product '$PROD' exists."
    fi
done

# 4. Ensure Application is ready
echo "--- Ensuring iDempiere is ready ---"
if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to dashboard to ensure clean state
ensure_idempiere_open ""
sleep 5

# 5. Capture Initial State
echo "Capturing initial screenshot..."
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="