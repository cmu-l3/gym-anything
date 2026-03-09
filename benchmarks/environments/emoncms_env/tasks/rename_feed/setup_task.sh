#!/bin/bash
# Task setup: rename_feed
# Ensures the 'Appliances' feed exists with the original name before agent renames it.

source /workspace/scripts/task_utils.sh

echo "=== Setting up rename_feed task ==="

wait_for_emoncms

APIKEY=$(get_apikey_write)

# Reset the feed name back to 'Appliances' and tag to 'power' (clean state)
FEED_ID=$(db_query "SELECT id FROM feeds WHERE (name='Appliances' OR name='Appliances Power') AND userid=1" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    curl -s "${EMONCMS_URL}/feed/set.json?apikey=${APIKEY}&id=${FEED_ID}&fields=$(python3 -c 'import urllib.parse; print(urllib.parse.quote("{\"name\":\"Appliances\",\"tag\":\"power\"}"))')" >/dev/null 2>&1 || true
    # Also update directly in DB to be safe
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms \
        -e "UPDATE feeds SET name='Appliances', tag='power' WHERE id=${FEED_ID}" 2>/dev/null || true
    echo "Reset feed name to 'Appliances', tag='power' (id=${FEED_ID})"
else
    echo "Warning: 'Appliances' feed not found, creating it..."
    curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY}&name=Appliances&tag=power&datatype=1&engine=5&options=%7B%22interval%22%3A10%7D&unit=W" >/dev/null 2>&1 || true
fi

# Navigate to Feeds list page
launch_firefox_to "http://localhost/feed/list" 5

# Take a starting screenshot
take_screenshot /tmp/task_rename_feed_start.png

echo "=== Task setup complete: rename_feed ==="
