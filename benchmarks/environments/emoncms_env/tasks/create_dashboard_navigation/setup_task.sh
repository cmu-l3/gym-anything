#!/bin/bash
# Setup script for Create Dashboard Navigation task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Create Dashboard Navigation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# Get API Key
APIKEY=$(get_apikey_write)

# Function to ensure a dashboard exists
ensure_dashboard() {
    local name="$1"
    local existing_id
    existing_id=$(db_query "SELECT id FROM dashboard WHERE name='$name' AND userid=1" 2>/dev/null | head -1)
    
    if [ -z "$existing_id" ]; then
        echo "Creating dashboard: $name"
        # Create via API
        # Note: encoding spaces for URL
        local url_name=$(echo "$name" | sed 's/ /%20/g')
        curl -s "${EMONCMS_URL}/dashboard/create.json?apikey=${APIKEY}&name=${url_name}" > /dev/null
        sleep 1
        existing_id=$(db_query "SELECT id FROM dashboard WHERE name='$name' AND userid=1" 2>/dev/null | head -1)
    fi
    echo "$existing_id"
}

# 1. Ensure Target Dashboards Exist
HVAC_ID=$(ensure_dashboard "HVAC Detail")
LIGHTING_ID=$(ensure_dashboard "Lighting Detail")
SOLAR_ID=$(ensure_dashboard "Solar Detail")

# 2. Ensure Landing Dashboard Exists and is EMPTY
LANDING_ID=$(ensure_dashboard "Facility Overview")

# Clear content of landing dashboard to ensure clean state
# Content is usually '[]' for empty or null
db_query "UPDATE dashboard SET content='[]' WHERE id=${LANDING_ID}"

echo "Setup Dashboards:"
echo "  Facility Overview (ID: $LANDING_ID)"
echo "  HVAC Detail (ID: $HVAC_ID)"
echo "  Lighting Detail (ID: $LIGHTING_ID)"
echo "  Solar Detail (ID: $SOLAR_ID)"

# Store expected mapping for export script (internal use only)
cat > /tmp/dashboard_ids.json << EOF
{
    "landing_id": $LANDING_ID,
    "targets": {
        "HVAC": $HVAC_ID,
        "Lighting": $LIGHTING_ID,
        "Solar": $SOLAR_ID
    }
}
EOF

# 3. Launch Firefox and login
launch_firefox_to "http://localhost/dashboard/list" 5

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="