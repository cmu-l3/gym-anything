#!/bin/bash
# Export script for External Outbound Link Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting External Outbound Link Audit Result ==="

# 1. Capture final state evidence
take_screenshot /tmp/task_end_screenshot.png

# 2. Gather Configuration
EXPORT_DIR="/home/ga/Documents/SEO/exports"
REPORTS_DIR="/home/ga/Documents/SEO/reports"
REPORT_PATH="$REPORTS_DIR/external_links_report.txt"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")

# 3. Variables to populate
SF_RUNNING="false"
CSV_CREATED="false"
CSV_PATH=""
EXTERNAL_LINKS_FOUND=0
UNIQUE_EXTERNAL_DOMAINS=0
REPORT_EXISTS="false"
REPORT_SIZE=0
REPORT_HAS_NUMBERS="false"
REPORT_HAS_ACTION="false"
REPORT_MENTIONS_DOMAINS="false"
WINDOW_INFO=""

# 4. Check System State
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi
WINDOW_INFO=$(su - ga -c "DISPLAY=:1 wmctrl -l 2>/dev/null" | grep -i "screaming\|spider" | head -1 || echo "")

# 5. Analyze Exported CSVs
# We look for a CSV created AFTER task start that contains external links
if [ -d "$EXPORT_DIR" ]; then
    # Find newest CSV
    while IFS= read -r -d '' csv_file; do
        FILE_EPOCH=$(stat -c %Y "$csv_file" 2>/dev/null || echo "0")
        
        if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
            # Found a candidate CSV
            
            # Check for header columns typical of External or Outlinks export
            # External tab export: "Address", "Content", "Status Code"
            # Bulk Export > Outlinks: "Source", "Destination", "Anchor"
            HEADER=$(head -1 "$csv_file" 2>/dev/null || echo "")
            
            IS_RELEVANT_CSV="false"
            if echo "$HEADER" | grep -qi "Address\|Destination\|External"; then
                IS_RELEVANT_CSV="true"
            fi

            if [ "$IS_RELEVANT_CSV" = "true" ]; then
                # Count external links (URLs NOT containing crawler-test.com)
                # We assume standard CSV structure where URLs are present
                # grep -v "crawler-test.com" excludes internal links
                # grep "http" ensures it's a URL
                
                # Note: This is a heuristic. A robust check would parse CSV columns.
                # Here we check if the file contains http links that are NOT the target domain.
                
                EXT_COUNT=$(grep "http" "$csv_file" | grep -v "crawler-test.com" | wc -l)
                
                if [ "$EXT_COUNT" -gt 0 ]; then
                    CSV_CREATED="true"
                    CSV_PATH="$csv_file"
                    EXTERNAL_LINKS_FOUND=$EXT_COUNT
                    
                    # Estimate unique domains using simple processing
                    # Extract domain from URLs (simplistic regex)
                    UNIQUE_DOMAINS=$(grep "http" "$csv_file" | grep -v "crawler-test.com" | grep -oE 'https?://[^/"]+' | sort | uniq | wc -l)
                    UNIQUE_EXTERNAL_DOMAINS=$UNIQUE_DOMAINS
                    
                    # If we found a good candidate, stop looking (or keep looking for a better one?)
                    # Let's take the one with the most external data
                    break
                fi
            fi
        fi
    done < <(find "$EXPORT_DIR" -name "*.csv" -type f -print0 2>/dev/null)
fi

# 6. Analyze Text Report
if [ -f "$REPORT_PATH" ]; then
    FILE_EPOCH=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_EPOCH" -gt "$TASK_START_EPOCH" ]; then
        REPORT_EXISTS="true"
        REPORT_SIZE=$(stat -c %s "$REPORT_PATH" 2>/dev/null || echo "0")
        
        # Check content
        CONTENT=$(cat "$REPORT_PATH")
        
        # Check for numbers (counts)
        if echo "$CONTENT" | grep -qE "[0-9]+"; then
            REPORT_HAS_NUMBERS="true"
        fi
        
        # Check for actionable words
        if echo "$CONTENT" | grep -qiE "recommend|suggest|fix|audit|action|remove|add"; then
            REPORT_HAS_ACTION="true"
        fi
        
        # Check if report mentions typical external domains found on crawler-test.com
        # Common ones: google, facebook, twitter, example, yahoo, etc.
        # This confirms they actually looked at the data
        if echo "$CONTENT" | grep -qiE "google|facebook|twitter|example|yahoo|iana|w3\.org"; then
            REPORT_MENTIONS_DOMAINS="true"
        fi
    fi
fi

# 7. Generate JSON Result
python3 << PYEOF
import json

result = {
    "sf_running": "$SF_RUNNING" == "true",
    "window_info": """$WINDOW_INFO""",
    "csv_created": "$CSV_CREATED" == "true",
    "csv_path": "$CSV_PATH",
    "external_links_found_count": $EXTERNAL_LINKS_FOUND,
    "unique_external_domains_count": $UNIQUE_EXTERNAL_DOMAINS,
    "report_exists": "$REPORT_EXISTS" == "true",
    "report_size_bytes": $REPORT_SIZE,
    "report_has_numbers": "$REPORT_HAS_NUMBERS" == "true",
    "report_has_action": "$REPORT_HAS_ACTION" == "true",
    "report_mentions_domains": "$REPORT_MENTIONS_DOMAINS" == "true",
    "task_start_epoch": $TASK_START_EPOCH,
    "timestamp": "$(date -Iseconds)"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result exported to /tmp/task_result.json")
PYEOF

cat /tmp/task_result.json
echo "=== Export Complete ==="