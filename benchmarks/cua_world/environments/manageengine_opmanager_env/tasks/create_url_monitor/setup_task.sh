#!/bin/bash
echo "=== Setting up Create URL Monitor Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Verify OpManager is running (with extended timeout for slow starts)
echo "Checking OpManager health..."
if ! wait_for_opmanager_ready 120; then
    echo "WARNING: OpManager may not be fully ready"
fi

# Verify the target URL is actually accessible (real data validation)
echo "Verifying target URL is accessible..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:8060" 2>/dev/null)
echo "Target URL http://localhost:8060 returns HTTP $HTTP_CODE"

# Record timestamp
date +%s > /tmp/task_start_timestamp
date -Iseconds > /tmp/task_start_iso

# Ensure Firefox is running and showing OpManager (with retry/recovery)
echo "Ensuring Firefox is on OpManager dashboard..."
ensure_firefox_on_opmanager 3

# Take initial screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Create URL Monitor Task Setup Complete ==="
echo ""
echo "Task: Create a URL monitor in OpManager"
echo "  Monitor Name: OpManager Self-Check"
echo "  Target URL: http://localhost:8060"
echo "  Polling Interval: 5 minutes"
echo ""
echo "OpManager Login: admin / Admin@123"
echo "OpManager URL: $OPMANAGER_URL"
echo ""
