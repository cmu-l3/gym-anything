#!/bin/bash
set -e
echo "=== Setting up task: restrict_cod_to_local_pickup ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for database
for i in {1..30}; do
    if check_db_connection; then
        break
    fi
    sleep 2
done

# 1. Clean up existing zones to ensure known state
echo "Cleaning existing shipping zones..."
wp wc shipping_zone list --format=json --user=admin --allow-root | jq -r '.[].id' | xargs -I % wp wc shipping_zone delete % --force --user=admin --allow-root > /dev/null 2>&1 || true

# 2. Create 'San Francisco Local' Zone
echo "Creating Local Zone..."
ZONE_JSON=$(wp wc shipping_zone create --name="San Francisco Local" --order=1 --user=admin --allow-root --format=json)
ZONE_ID=$(echo "$ZONE_JSON" | jq -r '.id')

# 3. Add Postcode restriction (94105)
echo "Adding location to zone..."
wp wc shipping_zone_location create "$ZONE_ID" --code="94105" --type="postcode" --user=admin --allow-root > /dev/null

# 4. Add 'Local Pickup' Method (Target)
echo "Adding Local Pickup method..."
PICKUP_JSON=$(wp wc shipping_zone_method create "$ZONE_ID" --method_id="local_pickup" --enabled=true --user=admin --allow-root --format=json)
# Save the instance ID for verification (e.g., local_pickup:1)
PICKUP_INSTANCE_ID=$(echo "$PICKUP_JSON" | jq -r '.instance_id')
TARGET_METHOD_ID="local_pickup:$PICKUP_INSTANCE_ID"
echo "$TARGET_METHOD_ID" > /tmp/target_method_id.txt
echo "Target Method ID: $TARGET_METHOD_ID"

# 5. Add 'Flat Rate' Method (Distractor)
echo "Adding Flat Rate method..."
FLAT_JSON=$(wp wc shipping_zone_method create "$ZONE_ID" --method_id="flat_rate" --enabled=true --settings='{"cost":"5.00"}' --user=admin --allow-root --format=json)
FLAT_INSTANCE_ID=$(echo "$FLAT_JSON" | jq -r '.instance_id')
DISTRACTOR_METHOD_ID="flat_rate:$FLAT_INSTANCE_ID"
echo "$DISTRACTOR_METHOD_ID" > /tmp/distractor_method_id.txt
echo "Distractor Method ID: $DISTRACTOR_METHOD_ID"

# 6. Reset COD Settings to default (Disabled, no restrictions)
echo "Resetting COD settings..."
# We create a default config structure
# Note: enable_for_methods: "" means 'Any method' in WooCommerce logic if empty string.
wp option update woocommerce_cod_settings '{"enabled":"no","title":"Cash on delivery","description":"Pay with cash upon delivery.","instructions":"Pay with cash upon delivery.","enable_for_methods":"","enable_for_virtual":"yes"}' --format=json --allow-root

# CRITICAL: Ensure WordPress admin page is showing
echo "Ensuring WordPress admin page is displayed..."
if ! ensure_wordpress_shown 60; then
    echo "FATAL: Could not load WordPress admin page - task cannot proceed"
    exit 1
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Task setup complete ==="