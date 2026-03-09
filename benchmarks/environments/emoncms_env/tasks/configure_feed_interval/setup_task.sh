#!/bin/bash
# Task setup: configure_feed_interval
# Resets the 'House Temperature' feed interval to 10s before the agent changes it to 60s.

source /workspace/scripts/task_utils.sh

echo "=== Setting up configure_feed_interval task ==="

wait_for_emoncms

APIKEY=$(get_apikey_write)

# Reset the interval for 'House Temperature' feed to 10 (clean state)
FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='House Temperature' AND userid=1" 2>/dev/null | head -1)
if [ -n "$FEED_ID" ]; then
    # Update interval in database
    docker exec emoncms-db mysql -u emoncms -pemoncms emoncms \
        -e "UPDATE feeds SET interval=10 WHERE id=${FEED_ID}" 2>/dev/null || true
    echo "Reset 'House Temperature' interval to 10s (id=${FEED_ID})"
else
    echo "Warning: 'House Temperature' feed not found"
fi

# Navigate to Feeds list page
launch_firefox_to "http://localhost/feed/list" 5

# Take a starting screenshot
take_screenshot /tmp/task_configure_feed_interval_start.png

echo "=== Task setup complete: configure_feed_interval ==="
