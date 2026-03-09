#!/bin/bash
# Export script for Custom Header Auth Bypass Audit

source /workspace/scripts/task_utils.sh

echo "=== Exporting Result ==="

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Parameters
EXPECTED_FILE="/home/ga/Documents/SEO/exports/custom_header_evidence.csv"
TASK_START_EPOCH=$(cat /tmp/task_start_epoch 2>/dev/null || echo "0")
TARGET_URL_PART="crawler_request_headers"
REQUIRED_TOKEN="SF-Verified-9988"

# Initialize result variables
FILE_EXISTS="false"
FILE_CREATED_DURING_TASK="false"
URL_FOUND="false"
TOKEN_FOUND_IN_CSV="false"
SEARCH_MATCH_DETECTED="false"
SF_RUNNING="false"

# Check if SF is running
if is_screamingfrog_running; then
    SF_RUNNING="true"
fi

# Check file existence and timestamp
if [ -f "$EXPECTED_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$EXPECTED_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
        FILE_CREATED_DURING_TASK="true"
        
        # Analyze Content
        # 1. Check for URL
        if grep -q "$TARGET_URL_PART" "$EXPECTED_FILE"; then
            URL_FOUND="true"
        fi
        
        # 2. Check for Token text (evidence that search was configured for this token)
        if grep -q "$REQUIRED_TOKEN" "$EXPECTED_FILE"; then
            TOKEN_FOUND_IN_CSV="true"
        fi
        
        # 3. Check for positive match (Success)
        # Custom Search CSVs typically have a 'Contains' or 'Found' count > 0
        # If the header wasn't sent, the page wouldn't contain the token, 
        # so the search result would be 0 or "False" / empty.
        # We look for the row containing the URL, and ensure it has the token AND a non-zero count/match.
        
        # Extract the line with the URL
        URL_LINE=$(grep "$TARGET_URL_PART" "$EXPECTED_FILE" || echo "")
        
        # Simple heuristic: If the line contains the token AND the URL, and typically '1' or 'Found'
        # But even simpler: The token itself IS the search term. If it appears in the CSV content *columns* 
        # (not just header), it usually means it was found or is being reported.
        # However, specifically, we want to know if it was FOUND in the page.
        # A failed search might list the URL but have '0' for the count.
        
        # Check if "1" or higher exists in the line, or "Found"
        if [ -n "$URL_LINE" ]; then
             if echo "$URL_LINE" | grep -qE ",1,|,2,|,3,|Found|True"; then
                 SEARCH_MATCH_DETECTED="true"
             fi
        fi
    fi
else
    # Check if ANY CSV was exported if the specific name wasn't used
    LATEST_CSV=$(ls -t /home/ga/Documents/SEO/exports/*.csv 2>/dev/null | head -1)
    if [ -n "$LATEST_CSV" ]; then
        EXPECTED_FILE="$LATEST_CSV" # update path for reporting
        FILE_EXISTS="true"
        FILE_MTIME=$(stat -c %Y "$LATEST_CSV" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -gt "$TASK_START_EPOCH" ]; then
            FILE_CREATED_DURING_TASK="true"
            if grep -q "$TARGET_URL_PART" "$LATEST_CSV"; then URL_FOUND="true"; fi
            if grep -q "$REQUIRED_TOKEN" "$LATEST_CSV"; then TOKEN_FOUND_IN_CSV="true"; fi
            URL_LINE=$(grep "$TARGET_URL_PART" "$LATEST_CSV" || echo "")
            if [ -n "$URL_LINE" ]; then
                 if echo "$URL_LINE" | grep -qE ",1,|,2,|,3,|Found|True"; then
                     SEARCH_MATCH_DETECTED="true"
                 fi
            fi
        fi
    fi
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sf_running": $SF_RUNNING,
    "file_exists": $FILE_EXISTS,
    "file_path": "$EXPECTED_FILE",
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "url_found": $URL_FOUND,
    "token_found_in_csv": $TOKEN_FOUND_IN_CSV,
    "search_match_detected": $SEARCH_MATCH_DETECTED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Save result
rm -f /tmp/task_result.json 2>/dev/null
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json