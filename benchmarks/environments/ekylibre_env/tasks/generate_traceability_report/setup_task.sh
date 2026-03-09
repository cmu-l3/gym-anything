#!/bin/bash
echo "=== Setting up Generate Traceability Report Task ==="

source /workspace/scripts/task_utils.sh

# 1. Clean up Downloads directory to ensure we identify the NEW file
rm -f /home/ga/Downloads/*.pdf
rm -f /home/ga/Downloads/*.PDF
mkdir -p /home/ga/Downloads

# 2. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# 3. Wait for Ekylibre
wait_for_ekylibre 120

# 4. Launch Firefox to the Reports or Dashboard page
# Using the main dashboard or the reports index if known. 
# /backend/reports is often the index.
EKYLIBRE_BASE=$(detect_ekylibre_url)
TARGET_URL="${EKYLIBRE_BASE}/backend/reports"

echo "Navigating to: $TARGET_URL"
ensure_firefox_with_ekylibre "$TARGET_URL"
sleep 5

# 5. Maximize window for visibility
maximize_firefox

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target Field: Les Groies"
echo "Downloads cleared."