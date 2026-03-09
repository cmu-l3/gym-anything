#!/bin/bash
# Export script for configure_payment_gateway task
echo "=== Exporting configure_payment_gateway Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Get list of all payment gateways currently in the system
cd /var/www/html/drupal
CURRENT_GATEWAYS=$(vendor/bin/drush config:list --prefix=commerce_payment.commerce_payment_gateway 2>/dev/null)

# 2. Get list of initial gateways
INITIAL_GATEWAYS_FILE="/tmp/initial_gateways.txt"
if [ -f "$INITIAL_GATEWAYS_FILE" ]; then
    INITIAL_GATEWAYS=$(cat "$INITIAL_GATEWAYS_FILE")
else
    INITIAL_GATEWAYS=""
fi

# 3. Identify potential candidate gateways (newly created or modified)
# We will export the full config of ALL current gateways to JSON for the verifier to analyze.
# The verifier will search for the one matching the requirements.

echo "Exporting gateway configurations..."

# Create a temporary directory for config exports
EXPORT_DIR=$(mktemp -d)
JSON_OUTPUT="/tmp/payment_gateway_result.json"

# Start JSON array
echo "[" > "$JSON_OUTPUT"
FIRST=true

for config_name in $CURRENT_GATEWAYS; do
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$JSON_OUTPUT"
    fi

    # Check if this gateway existed initially
    IS_NEW="true"
    if echo "$INITIAL_GATEWAYS" | grep -q "$config_name"; then
        IS_NEW="false"
    fi

    # Export specific config to JSON
    # Drush config:get returns YAML by default, --format=json gives us JSON
    # We pipe it to jq to add the 'is_new' flag and ensure it's a single object
    CONFIG_JSON=$(vendor/bin/drush config:get "$config_name" --format=json 2>/dev/null)
    
    if [ -n "$CONFIG_JSON" ]; then
        # Add metadata about newness and config name
        echo "$CONFIG_JSON" | jq --arg is_new "$IS_NEW" --arg name "$config_name" '. + {is_new: $is_new, config_name: $name}' >> "$JSON_OUTPUT"
    else
        echo "{}" >> "$JSON_OUTPUT"
    fi
done

# End JSON array
echo "]" >> "$JSON_OUTPUT"

# Permissions fix
chmod 666 "$JSON_OUTPUT"

echo "Exported $(grep -c "config_name" "$JSON_OUTPUT") gateway configurations."
cat "$JSON_OUTPUT"

echo "=== Export Complete ==="