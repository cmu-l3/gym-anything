#!/bin/bash
# Export script for Site Architecture Visualization task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Task Result ==="

# 1. Take final screenshot (evidence of UI state)
take_screenshot /tmp/task_final.png

# 2. Define expected output paths
OUTPUT_FILE="/home/ga/Documents/SEO/exports/site_graph.html"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Check file existence and metadata
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
FILE_SIZE=0
CONTENT_VALID="false"
DOMAIN_FOUND="false"

if [ -f "$OUTPUT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_FILE")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE")

    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # Check content (Basic HTML validation and keyword search)
    # Screaming Frog graphs usually contain JS libraries or specific strings
    # We look for common HTML tags and potentially "sigma" or "echarts" or "d3" or just "Screaming Frog"
    if grep -qi "html" "$OUTPUT_FILE" && grep -qi "body" "$OUTPUT_FILE"; then
        # It is HTML
        if [ "$FILE_SIZE" -gt 1024 ]; then
            # Arbitrary small size check
            CONTENT_VALID="true"
        fi
        
        # Check for target domain in the file (visualization usually embeds node data)
        if grep -qi "books.toscrape.com" "$OUTPUT_FILE"; then
            DOMAIN_FOUND="true"
        fi
    fi
fi

# 4. Check if Screaming Frog is still running (optional but good context)
APP_RUNNING="false"
if is_screamingfrog_running; then
    APP_RUNNING="true"
fi

# 5. Check if a Visualization window is open (using wmctrl)
# This helps confirm they actually opened the tool, not just curled a file
VISUALIZATION_WINDOW_OPEN="false"
if DISPLAY=:1 wmctrl -l | grep -qi "Crawl Diagram"; then
    VISUALIZATION_WINDOW_OPEN="true"
fi

# 6. Generate JSON result
# Use python for robust JSON generation
python3 << PYEOF
import json
import os

result = {
    "file_exists": "$FILE_EXISTS" == "true",
    "file_created_during_task": "$FILE_CREATED_DURING_TASK" == "true",
    "file_size_bytes": $FILE_SIZE,
    "content_looks_like_html_graph": "$CONTENT_VALID" == "true",
    "target_domain_in_file": "$DOMAIN_FOUND" == "true",
    "app_running": "$APP_RUNNING" == "true",
    "visualization_window_detected": "$VISUALIZATION_WINDOW_OPEN" == "true",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Exported result to /tmp/task_result.json")
PYEOF

# 7. Print result for log
cat /tmp/task_result.json
echo "=== Export Complete ==="