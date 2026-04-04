#!/bin/bash
set -e
echo "=== Exporting Configure Business Details Results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------------------
# Scrape Final State from Manager.io
# ---------------------------------------------------------------------------
COOKIE_FILE="/tmp/mgr_export_cookies.txt"
rm -f "$COOKIE_FILE"

# Login
curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" \
    -X POST "http://localhost:8080/login" \
    -d "Username=administrator" \
    -L -o /dev/null

# Get Business Key (use cached or fetch new)
if [ -f /tmp/manager_biz_key.txt ]; then
    BIZ_KEY=$(cat /tmp/manager_biz_key.txt)
else
    BIZ_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/businesses" -L)
    BIZ_KEY=$(python3 -c "
import re, sys
html = sys.stdin.read()
m = re.search(r'start\?([^\"&\s]+)[^<]{0,300}Northwind', html)
if not m:
    m = re.search(r'start\?([^\"&\s]+)', html)
print(m.group(1) if m else '', end='')
" <<< "$BIZ_PAGE")
fi

echo "Using Business Key: $BIZ_KEY"

CONTENT_CAPTURED="false"
FINAL_HTML=""
SUMMARY_HTML=""

if [ -n "$BIZ_KEY" ]; then
    # Enter business
    curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/start?$BIZ_KEY" -L -o /dev/null

    # 1. Get Settings Page (often shows summary of details)
    SETTINGS_PAGE=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/settings?$BIZ_KEY" -L)
    
    # 2. Get Business Details Form (contains input fields with values)
    BD_FORM_URL=$(echo "$SETTINGS_PAGE" | grep -o '/business-details-form[^"]*' | head -1)
    if [ -n "$BD_FORM_URL" ]; then
        FINAL_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080$BD_FORM_URL" -L)
    else
        FINAL_HTML="$SETTINGS_PAGE"
    fi
    
    # 3. Get Business Details View (read-only view if exists)
    BD_VIEW_URL=$(echo "$SETTINGS_PAGE" | grep -o '/business-details?[^"]*' | grep -v 'form' | head -1)
    if [ -n "$BD_VIEW_URL" ]; then
        VIEW_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080$BD_VIEW_URL" -L)
        FINAL_HTML="${FINAL_HTML} ${VIEW_HTML}"
    fi

    # 4. Get Summary Page (Header usually contains Business Name)
    SUMMARY_HTML=$(curl -s -c "$COOKIE_FILE" -b "$COOKIE_FILE" "http://localhost:8080/summary?$BIZ_KEY" -L)
    
    CONTENT_CAPTURED="true"
fi

# Load initial state for comparison
INITIAL_CONTENT=""
if [ -f /tmp/initial_bd_content.html ]; then
    INITIAL_CONTENT=$(cat /tmp/initial_bd_content.html)
fi

# Prepare JSON Export using Python for safe string handling
python3 -c "
import json
import os
import time

try:
    final_html = os.environ.get('FINAL_HTML', '')
    summary_html = os.environ.get('SUMMARY_HTML', '')
    initial_content = os.environ.get('INITIAL_CONTENT', '')
    
    # Combine content for robust searching
    combined_content = final_html + ' ' + summary_html
    
    result = {
        'timestamp': time.time(),
        'content_captured': os.environ.get('CONTENT_CAPTURED') == 'true',
        'final_content': combined_content,
        'initial_content': initial_content,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(result, f)
        
except Exception as e:
    print(f'Error creating JSON: {e}')
    # Fallback JSON
    with open('/tmp/task_result.json', 'w') as f:
        json.dump({'error': str(e), 'content_captured': False}, f)
"

# Set permissions
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"