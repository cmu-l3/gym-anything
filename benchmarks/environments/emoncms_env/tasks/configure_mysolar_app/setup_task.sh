#!/bin/bash
set -e
echo "=== Setting up Configure MySolar App Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

APIKEY=$(get_apikey_write)

# -----------------------------------------------------------------------
# 1. Ensure required feeds exist with specific names
# -----------------------------------------------------------------------
echo "Ensuring required feeds exist..."

create_feed_if_missing() {
    local name="$1"
    local tag="$2"
    local existing_id=$(db_query "SELECT id FROM feeds WHERE name='$name' AND userid=1" 2>/dev/null | head -1)
    
    if [ -z "$existing_id" ]; then
        echo "Creating feed: $name"
        # Create feed via API
        # datatype=1 (realtime), engine=5 (PHPFina), interval=10
        local result=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=${name}&tag=${tag}&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W")
        local new_id=$(echo "$result" | grep -oE '"feedid":[0-9]+' | cut -d':' -f2)
        
        if [ -n "$new_id" ]; then
            # Insert some dummy data so it looks real
            curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${new_id}&time=$(date +%s)&value=1200" >/dev/null
            echo "Created feed $name with ID $new_id"
        else
            echo "Failed to create feed $name"
        fi
    else
        echo "Feed $name already exists (ID: $existing_id)"
    fi
}

create_feed_if_missing "solar_power" "Solar"
create_feed_if_missing "house_power" "House"
create_feed_if_missing "solar_energy_kwh" "Solar"
create_feed_if_missing "house_energy_kwh" "House"

# -----------------------------------------------------------------------
# 2. Clear existing MySolar configuration
# -----------------------------------------------------------------------
echo "Clearing MySolar app configuration..."

# Check if config exists in MySQL
# The 'app_config' table usually stores this. Structure: userid, app, name, description, config (json)
# Or sometimes 'apps' table depending on version. 
# We'll try to delete via API if possible, or DB.
# Since we don't have a reliable delete API for apps in all versions, we'll try DB.

# Try to clear via DB directly to be sure
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "DELETE FROM app_config WHERE name='mysolar' AND userid=1" 2>/dev/null || true

# Also check for 'apps' table (older versions)
docker exec emoncms-db mysql -u emoncms -pemoncms emoncms -e "DELETE FROM apps WHERE name='My Solar' AND userid=1" 2>/dev/null || true

echo "MySolar configuration cleared."

# -----------------------------------------------------------------------
# 3. Launch Firefox to the App page
# -----------------------------------------------------------------------
echo "Launching Firefox..."
# Note: The URL might be /app/view?name=MySolar or just /app depending on installation
# We'll go to the main app list or direct link if possible.
APP_URL="http://localhost/app/view?name=MySolar"

launch_firefox_to "$APP_URL" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="