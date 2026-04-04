#!/bin/bash
# Export result script with error handling

# Trap errors to ensure result file is always created
trap 'ensure_result_file /tmp/task_result.json "export script error: $?"' ERR

source /workspace/scripts/task_utils.sh

echo "=== Exporting Broken Fragment Audit Result ==="

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/Documents/SEO/exports"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# Initialize result variables
FILE_CREATED="false"
FRAGMENT_CONFIG_VERIFIED="false"
BROKEN_BOOKMARK_FOUND="false"
EXPORT_FILE_PATH=""
ROW_COUNT=0

# Check if Screaming Frog is still running
if is_screamingfrog_running; then
    SF_RUNNING="true"
else
    SF_RUNNING="false"
fi

# Look for CSV files created/modified after task start
# We look for ANY CSV in the export directory
while IFS= read -r -d '' csv_file; do
    if [ -f "$csv_file" ]; then
        FILE_MTIME=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        # Check if file is new/modified
        if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
            echo "Analyzing export file: $csv_file"
            
            # 1. Check if file was created (we found one!)
            FILE_CREATED="true"
            EXPORT_FILE_PATH="$csv_file"
            
            # Count rows (excluding header)
            ROWS=$(wc -l < "$csv_file")
            ROW_COUNT=$((ROWS - 1))
            
            # Read file content for verification
            # We look for the '#' character in URLs, which proves fragment crawling was enabled
            # Standard crawl exports strip the '#'
            if grep -q "#" "$csv_file"; then
                FRAGMENT_CONFIG_VERIFIED="true"
                echo "  -> Found '#' characters in URL data (Config Verified)"
            fi
            
            # Check specifically for the known broken bookmark on crawler-test.com
            # Usually "#broken_bookmark" or "broken_bookmark" in the anchor column
            if grep -qi "broken_bookmark" "$csv_file"; then
                BROKEN_BOOKMARK_FOUND="true"
                echo "  -> Found specific 'broken_bookmark' entry"
            fi
            
            # If we found a file with fragments, we can stop searching (assuming this is the correct export)
            if [ "$FRAGMENT_CONFIG_VERIFIED" = "true" ]; then
                break
            fi
        fi
    fi
done < <(find "$EXPORT_DIR" -name "*.csv" -print0)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "screaming_frog_running": $SF_RUNNING,
    "file_created": $FILE_CREATED,
    "export_file_path": "$EXPORT_FILE_PATH",
    "fragment_config_verified": $FRAGMENT_CONFIG_VERIFIED,
    "broken_bookmark_found": $BROKEN_BOOKMARK_FOUND,
    "row_count": $ROW_COUNT,
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