#!/bin/bash
set -e
echo "=== Setting up create_conversion_rate task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Record initial count of relevant conversion rates
# We specifically look for EUR->USD rates covering 2025 to detect if one already exists (unlikely in seed data)
echo "--- Recording initial state ---"
CLIENT_ID=$(get_gardenworld_client_id)

INITIAL_COUNT=$(idempiere_query "
    SELECT COUNT(*) 
    FROM c_conversion_rate cr
    JOIN c_currency cf ON cr.c_currency_id = cf.c_currency_id
    JOIN c_currency ct ON cr.c_currency_id_to = ct.c_currency_id
    WHERE cf.iso_code='EUR' AND ct.iso_code='USD'
    AND cr.validfrom <= '2025-01-01' AND cr.validto >= '2025-12-31'
    AND cr.ad_client_id=${CLIENT_ID:-11}
" 2>/dev/null || echo "0")

echo "$INITIAL_COUNT" > /tmp/initial_rate_count.txt
echo "Initial relevant conversion rates: $INITIAL_COUNT"

# 3. Ensure Firefox is running and navigate to iDempiere dashboard
echo "--- Navigating to iDempiere ---"
if ! pgrep -f firefox > /dev/null 2>&1; then
    echo "  Firefox not running, launching..."
    su - ga -c "DISPLAY=:1 firefox https://localhost:8443/webui/ &"
    sleep 15
fi

# Navigate to iDempiere dashboard
ensure_idempiere_open ""

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 3

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png
echo "  Initial screenshot saved to /tmp/task_initial.png"

echo "=== Task setup complete ==="