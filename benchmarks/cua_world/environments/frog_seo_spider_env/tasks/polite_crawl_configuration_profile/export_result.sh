#!/bin/bash
# Export script for Polite Crawl Configuration Profile task

source /workspace/scripts/task_utils.sh

echo "=== Exporting Result ==="

take_screenshot /tmp/task_end_screenshot.png

TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Paths defined in task
CONFIG_PATH="/home/ga/Documents/SEO/configs/polite_profile.seospiderconfig"
EXPORT_PATH="/home/ga/Documents/SEO/exports/polite_crawl_data.csv"
SPEED_SCREENSHOT="/home/ga/Documents/SEO/reports/speed_settings.png"
UA_SCREENSHOT="/home/ga/Documents/SEO/reports/ua_settings.png"

# Initialize result variables
CONFIG_EXISTS="false"
CONFIG_SIZE=0
EXPORT_EXISTS="false"
EXPORT_ROWS=0
EXPORT_HAS_DOMAIN="false"
SPEED_IMG_EXISTS="false"
UA_IMG_EXISTS="false"
SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# 1. Verify Config File
if [ -f "$CONFIG_PATH" ]; then
    MTIME=$(stat -c %Y "$CONFIG_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START_EPOCH" ]; then
        CONFIG_EXISTS="true"
        CONFIG_SIZE=$(stat -c %s "$CONFIG_PATH" 2>/dev/null || echo "0")
        
        # Try to grep the config for "AuditBot" or thread settings (files are often binary/compressed, but sometimes text xml)
        # We won't rely on this for scoring, just info
        if grep -aq "AuditBot" "$CONFIG_PATH"; then
            echo "Found 'AuditBot' in config file"
        fi
    fi
fi

# 2. Verify Export File
if [ -f "$EXPORT_PATH" ]; then
    MTIME=$(stat -c %Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START_EPOCH" ]; then
        EXPORT_EXISTS="true"
        # Count rows (subtract header)
        TOTAL_LINES=$(wc -l < "$EXPORT_PATH" 2>/dev/null || echo "0")
        if [ "$TOTAL_LINES" -gt 1 ]; then
            EXPORT_ROWS=$((TOTAL_LINES - 1))
        fi
        
        # Check domain
        if grep -q "books.toscrape.com" "$EXPORT_PATH"; then
            EXPORT_HAS_DOMAIN="true"
        fi
    fi
fi

# 3. Verify Screenshots
if [ -f "$SPEED_SCREENSHOT" ]; then
    MTIME=$(stat -c %Y "$SPEED_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START_EPOCH" ]; then
        SPEED_IMG_EXISTS="true"
    fi
fi

if [ -f "$UA_SCREENSHOT" ]; then
    MTIME=$(stat -c %Y "$UA_SCREENSHOT" 2>/dev/null || echo "0")
    if [ "$MTIME" -gt "$TASK_START_EPOCH" ]; then
        UA_IMG_EXISTS="true"
    fi
fi

# Write result JSON
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "config_exists": "$CONFIG_EXISTS" == "true",
    "config_size": $CONFIG_SIZE,
    "export_exists": "$EXPORT_EXISTS" == "true",
    "export_rows": $EXPORT_ROWS,
    "export_has_domain": "$EXPORT_HAS_DOMAIN" == "true",
    "speed_screenshot_exists": "$SPEED_IMG_EXISTS" == "true",
    "ua_screenshot_exists": "$UA_IMG_EXISTS" == "true",
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export Complete ==="