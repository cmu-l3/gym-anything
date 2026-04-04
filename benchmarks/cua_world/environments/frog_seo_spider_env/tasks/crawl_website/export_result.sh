#!/bin/bash
# Export result script with error handling

# Trap errors to ensure result file is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Crawl Website Result ==="

# Take final screenshot
take_screenshot /tmp/screamingfrog_crawl_final.png

# Check crawl status from Screaming Frog window
WINDOW_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null)
SF_WINDOW=$(echo "$WINDOW_LIST" | grep -i "screaming frog\|seo spider" | head -1)

# Gather information about the crawl
CRAWL_DETECTED="false"
CRAWL_STATUS="unknown"
URL_COUNT=0
HAS_RESULTS="false"

if [ -n "$SF_WINDOW" ]; then
    echo "Screaming Frog window found: $SF_WINDOW"

    # STRICT: Only detect crawl if window title shows crawler-test.com
    # This prevents false positives from just having "http" in title
    if echo "$SF_WINDOW" | grep -qi "crawler-test"; then
        CRAWL_DETECTED="true"
        CRAWL_STATUS="complete"
        echo "Correct URL (crawler-test.com) found in window title"
    elif echo "$SF_WINDOW" | grep -qi "http"; then
        # Some URL was crawled but NOT crawler-test.com
        CRAWL_DETECTED="false"
        CRAWL_STATUS="wrong_url"
        echo "WARNING: Some URL crawled but NOT crawler-test.com"
    fi
fi

# Try to extract URL count from Screaming Frog's status bar or internal files
# Check ~/.ScreamingFrogSEOSpider for crawl data
SF_DATA_DIR="/home/ga/.ScreamingFrogSEOSpider"
if [ -d "$SF_DATA_DIR" ]; then
    # Look for recent crawl data files
    CRAWL_DATA=$(find "$SF_DATA_DIR" -name "*.seospider" -mmin -10 2>/dev/null | head -1)
    if [ -n "$CRAWL_DATA" ]; then
        echo "Found recent crawl data: $CRAWL_DATA"
    fi
fi

# Check for any CSV export files created
EXPORT_DIR="/home/ga/Documents/SEO/exports"
LATEST_EXPORT=$(ls -t "$EXPORT_DIR"/*.csv 2>/dev/null | head -1)
INITIAL_COUNT=$(cat /tmp/initial_export_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l)

if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    HAS_RESULTS="true"
    if [ -n "$LATEST_EXPORT" ]; then
        URL_COUNT=$(count_urls_in_export "$LATEST_EXPORT")
        echo "Found $URL_COUNT URLs in export file"

        # Verify export contains crawler-test.com URLs
        if grep -qi "crawler-test" "$LATEST_EXPORT" 2>/dev/null; then
            echo "Export contains crawler-test.com URLs - verified"
        else
            echo "WARNING: Export does NOT contain crawler-test.com URLs"
            URL_COUNT=0  # Reset if wrong domain
        fi
    fi
fi

# Check if Screaming Frog is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
else
    SF_RUNNING="false"
fi

# Create JSON result in temp file first
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screaming_frog_running": $SF_RUNNING,
    "crawl_detected": $CRAWL_DETECTED,
    "crawl_status": "$CRAWL_STATUS",
    "has_export_results": $HAS_RESULTS,
    "url_count": $URL_COUNT,
    "initial_export_count": $INITIAL_COUNT,
    "current_export_count": $CURRENT_COUNT,
    "latest_export_file": "$LATEST_EXPORT",
    "window_info": "$(echo "$SF_WINDOW" | sed 's/"/\\"/g')",
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
