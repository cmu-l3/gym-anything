#!/bin/bash
# Export result script with error handling

# Trap errors to ensure result file is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Find Broken Links Result ==="

# Take final screenshot
take_screenshot /tmp/screamingfrog_broken_links_final.png

# Initialize variables - NO ASSUMPTIONS
CRAWL_PERFORMED="false"
BROKEN_LINK_FOUND="false"
RESPONSE_CODES_CHECKED="false"

# Check if Screaming Frog is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
    # NOTE: Do NOT assume crawl was performed just because SF is running
else
    SF_RUNNING="false"
fi

# Check window title for hints
WINDOW_INFO=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "screaming frog\|seo spider" | head -1)

# STRICT: Only set CRAWL_PERFORMED if window shows crawler-test.com
if echo "$WINDOW_INFO" | grep -qi "crawler-test"; then
    CRAWL_PERFORMED="true"
    echo "Detected crawler-test.com in window title"
elif echo "$WINDOW_INFO" | grep -qi "http"; then
    # Some URL crawled but NOT the correct one
    echo "WARNING: Some URL crawled but NOT crawler-test.com"
fi

# Try to find export files that might contain broken link data
EXPORT_DIR="/home/ga/Documents/SEO/exports"
CLIENT_ERROR_FILE=""
TASK_START_TIME=$(cat /tmp/task_start_time 2>/dev/null || echo "1970-01-01T00:00:00")

# STRICT: Only count files created/modified AFTER task started AND containing crawler-test.com
# This prevents false positives from old export files
BROKEN_LINK_IN_EXPORT="false"
for csv_file in "$EXPORT_DIR"/*.csv; do
    if [ -f "$csv_file" ]; then
        # Check if file was modified after task started
        FILE_MTIME=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        TASK_START_EPOCH=$(date -d "$TASK_START_TIME" +%s 2>/dev/null || echo "0")

        # Only check files modified after task started
        if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
            # STRICT: Must contain BOTH 404 AND crawler-test to count
            if grep -qi "404\|not found\|client error" "$csv_file" 2>/dev/null; then
                if grep -qi "crawler-test" "$csv_file" 2>/dev/null; then
                    BROKEN_LINK_IN_EXPORT="true"
                    BROKEN_LINK_FOUND="true"
                    RESPONSE_CODES_CHECKED="true"
                    CLIENT_ERROR_FILE="$csv_file"
                    echo "Found 404 errors for crawler-test.com in recent export: $csv_file"
                    break
                fi
            fi
            # Check if file contains response code data for crawler-test.com
            if grep -qi "status\|response" "$csv_file" 2>/dev/null; then
                if grep -qi "crawler-test" "$csv_file" 2>/dev/null; then
                    RESPONSE_CODES_CHECKED="true"
                    echo "Found response code data for crawler-test.com in: $csv_file"
                fi
            fi
        fi
    fi
done

# NOTE: We do NOT set RESPONSE_CODES_CHECKED based on file name patterns alone
# It must contain actual response code data for crawler-test.com

# Check Screaming Frog logs if available - but only for crawler-test.com entries
SF_LOG="/tmp/screamingfrog_ga.log"
if [ -f "$SF_LOG" ]; then
    # Only check log entries that mention crawler-test.com
    if grep -qi "crawler-test" "$SF_LOG" 2>/dev/null; then
        if grep -i "crawler-test" "$SF_LOG" 2>/dev/null | grep -qi "404\|not found\|client error"; then
            BROKEN_LINK_FOUND="true"
            echo "Found 404 in logs for crawler-test.com"
        fi
        if grep -i "crawler-test" "$SF_LOG" 2>/dev/null | grep -qi "response\|status"; then
            RESPONSE_CODES_CHECKED="true"
            echo "Found response code info in logs for crawler-test.com"
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screaming_frog_running": $SF_RUNNING,
    "crawl_performed": $CRAWL_PERFORMED,
    "response_codes_checked": $RESPONSE_CODES_CHECKED,
    "broken_link_found": $BROKEN_LINK_FOUND,
    "broken_link_in_export": $BROKEN_LINK_IN_EXPORT,
    "client_error_export_file": "$CLIENT_ERROR_FILE",
    "window_info": "$(echo "$WINDOW_INFO" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="
