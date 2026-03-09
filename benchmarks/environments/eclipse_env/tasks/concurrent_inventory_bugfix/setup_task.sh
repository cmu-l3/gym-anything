#!/bin/bash
echo "=== Setting up Concurrent Inventory Bug Fix Task ==="
source /workspace/scripts/task_utils.sh

# Copy project to home directory
echo "[SETUP] Copying inventory-service to /home/ga/..."
rm -rf /home/ga/inventory-service
cp -r /workspace/data/inventory-service /home/ga/inventory-service
chown -R ga:ga /home/ga/inventory-service

# Record start timestamp
date +%s > /tmp/task_start_timestamp
echo "Task started at: $(cat /tmp/task_start_timestamp)"

# Record initial state
INITIAL_CONCURRENT_COUNT=$(grep -r "java\.util\.concurrent\|AtomicInteger\|ConcurrentHashMap\|ReentrantLock\|synchronized" \
    /home/ga/inventory-service/src/main/java/ 2>/dev/null | wc -l)
echo "$INITIAL_CONCURRENT_COUNT" > /tmp/initial_concurrent_count
echo "Initial concurrent primitive count: $INITIAL_CONCURRENT_COUNT"

INITIAL_TEST_COUNT=$(find /home/ga/inventory-service/src/test -name "*.java" 2>/dev/null | wc -l)
echo "$INITIAL_TEST_COUNT" > /tmp/initial_test_count
echo "Initial test file count: $INITIAL_TEST_COUNT"

# Ensure Eclipse is running
ensure_display_ready

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
