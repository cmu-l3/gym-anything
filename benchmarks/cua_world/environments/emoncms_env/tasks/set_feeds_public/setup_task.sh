#!/bin/bash
# setup_task.sh — Set up the "set_feeds_public" task
# Creates three feeds (if needed), ensures they are NOT public, opens Feeds page.

source /workspace/scripts/task_utils.sh

echo "=== Setting up task: set_feeds_public ==="
date +%s > /tmp/task_start_time.txt

# -----------------------------------------------------------------------
# 1. Wait for Emoncms and Get Keys
# -----------------------------------------------------------------------
wait_for_emoncms || { echo "ERROR: Emoncms not reachable"; exit 1; }

APIKEY=$(get_apikey_write)
if [ -z "$APIKEY" ]; then
    echo "ERROR: Could not retrieve admin API key"
    exit 1
fi

# -----------------------------------------------------------------------
# 2. Helper: Create feed if missing
# -----------------------------------------------------------------------
create_feed_if_missing() {
    local name="$1"
    local tag="$2"
    local unit="$3"

    # Check existence via DB to be sure
    local existing
    existing=$(db_query "SELECT id FROM feeds WHERE name='${name}' LIMIT 1")
    
    if [ -n "$existing" ]; then
        echo "Feed '${name}' already exists (ID=${existing})"
    else
        echo "Creating feed '${name}'..."
        # Use API to create
        local result
        # Note: URL encoding for JSON options
        result=$(curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=${name}&tag=${tag}&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=${unit}")
        
        # Extract ID (simple python parse)
        local fid
        fid=$(echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('feedid',''))" 2>/dev/null)
        
        if [ -n "$fid" ]; then
            # Insert a sample data point so the feed isn't empty/null
            local now=$(date +%s)
            curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY}&id=${fid}&time=${now}&value=42.5" >/dev/null 2>&1
            echo "Created feed '${name}' with ID ${fid}"
        else
            echo "Failed to create feed '${name}'"
        fi
    fi
}

# -----------------------------------------------------------------------
# 3. Create Target and Distractor Feeds
# -----------------------------------------------------------------------
# Targets
create_feed_if_missing "campus_grid_power" "campus_energy" "W"
create_feed_if_missing "solar_array_output" "campus_energy" "W"
create_feed_if_missing "main_hall_temperature" "campus_environment" "C"

# Distractors (to test selectivity)
create_feed_if_missing "hvac_compressor_amps" "campus_hvac" "A"
create_feed_if_missing "server_room_humidity" "campus_it" "%"
create_feed_if_missing "ev_charger_power" "campus_transport" "W"

# -----------------------------------------------------------------------
# 4. Ensure ALL feeds are set to PRIVATE (clean slate)
# -----------------------------------------------------------------------
echo "Resetting all feeds to private..."
db_query "UPDATE feeds SET public=0"

# Verify initial state
INITIAL_PUBLIC=$(db_query "SELECT COUNT(*) FROM feeds WHERE public=1")
echo "Initial public feeds: ${INITIAL_PUBLIC}"
echo "${INITIAL_PUBLIC}" > /tmp/initial_public_count.txt

# -----------------------------------------------------------------------
# 5. Clear Redis cache
# -----------------------------------------------------------------------
# Emoncms caches feed metadata in Redis; direct DB updates might be hidden 
# without this flush.
docker exec emoncms-redis redis-cli FLUSHALL >/dev/null 2>&1 || true

# -----------------------------------------------------------------------
# 6. Launch Firefox to Feeds page
# -----------------------------------------------------------------------
echo "Launching Firefox..."
launch_firefox_to "http://localhost/feed/list" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="