#!/bin/bash
# Setup for audit_feed_storage task
set -u

echo "=== Setting up audit_feed_storage task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Emoncms is ready
wait_for_emoncms

# Ensure we have a mix of feed engines for a better test
# The default seed data usually uses PHPFina (engine 5).
# Let's verify we have at least one PHPTimeseries (engine 2) feed.
APIKEY_WRITE=$(get_apikey_write)
HAS_TS_FEED=$(db_query "SELECT count(*) FROM feeds WHERE engine=2" 2>/dev/null || echo "0")

if [ "$HAS_TS_FEED" -eq "0" ]; then
    echo "Creating a sample PHPTimeseries feed..."
    # Create feed via API
    # datatype=1 (realtime), engine=2 (PHPTimeseries)
    curl -s "${EMONCMS_URL}/feed/create.json?apikey=${APIKEY_WRITE}&name=legacy_sensor&tag=audit_test&datatype=1&engine=2&options=%7B%22interval%22%3A10%7D&unit=W" >/dev/null
    
    # Insert a data point to ensure meta files exist
    FEED_ID=$(db_query "SELECT id FROM feeds WHERE name='legacy_sensor' ORDER BY id DESC LIMIT 1" 2>/dev/null)
    if [ -n "$FEED_ID" ]; then
        TS=$(date +%s)
        curl -s "${EMONCMS_URL}/feed/insert.json?apikey=${APIKEY_WRITE}&id=${FEED_ID}&time=${TS}&value=123.45" >/dev/null
        echo "Created PHPTimeseries feed ID: $FEED_ID"
    fi
fi

# Remove any existing output file to ensure fresh creation
rm -f /home/ga/feed_storage_audit.csv

# Launch Firefox to the feed list page as a starting point
launch_firefox_to "http://localhost/feed/list" 5

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="