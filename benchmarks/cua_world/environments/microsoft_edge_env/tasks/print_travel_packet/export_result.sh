#!/bin/bash
# export_result.sh - Post-task hook for print_travel_packet
# Verifies file existence, content, and browser history.

echo "=== Exporting Print Travel Packet Result ==="

# Source utils if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/Documents/TravelPacket"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Helper to check PDF
check_pdf() {
    local filename="$1"
    local filepath="$OUTPUT_DIR/$filename"
    local required_keyword="$2"
    
    local exists="false"
    local size=0
    local created_after_start="false"
    local is_pdf="false"
    local has_keyword="false"
    local content_preview=""

    if [ -f "$filepath" ]; then
        exists="true"
        size=$(stat -c %s "$filepath")
        mtime=$(stat -c %Y "$filepath")
        
        if [ "$mtime" -gt "$TASK_START" ]; then
            created_after_start="true"
        fi

        # Check magic bytes (%PDF)
        if head -c 4 "$filepath" | grep -q "%PDF"; then
            is_pdf="true"
            
            # Extract text content
            if command -v pdftotext &> /dev/null; then
                pdftotext "$filepath" /tmp/pdf_content.txt
                if grep -qi "$required_keyword" /tmp/pdf_content.txt; then
                    has_keyword="true"
                fi
                # Save preview (first 200 chars) for debug
                content_preview=$(head -c 200 /tmp/pdf_content.txt | tr -d '\n\r"')
                rm -f /tmp/pdf_content.txt
            else
                # Fallback: strings check
                if strings "$filepath" | grep -qi "$required_keyword"; then
                    has_keyword="true"
                fi
            fi
        fi
    fi

    # Output JSON object for this file
    echo "{\"exists\": $exists, \"size\": $size, \"created_after_start\": $created_after_start, \"is_pdf\": $is_pdf, \"has_keyword\": $has_keyword, \"preview\": \"$content_preview\"}"
}

echo "Checking files..."

# Check each expected file
SCHENGEN_RESULT=$(check_pdf "schengen_area.pdf" "Schengen")
JETLAG_RESULT=$(check_pdf "jet_lag.pdf" "jet lag")
TRAVEL_DOC_RESULT=$(check_pdf "travel_documents.pdf" "passport")

# Check History
echo "Checking browser history..."
HISTORY_DB="/home/ga/.config/microsoft-edge/Default/History"
HISTORY_VISITS=""

if [ -f "$HISTORY_DB" ]; then
    # Copy DB to avoid locks
    cp "$HISTORY_DB" /tmp/history_check.db
    
    # Query for our target URLs visited AFTER task start
    # Edge/Chrome uses WebKit timestamp (microseconds since 1601). 
    # Current unix timestamp to WebKit: (unix + 11644473600) * 1000000
    # For simplicity, we just check if the URL exists in the table at all,
    # as the environment was likely fresh or we accept pre-existing history if the timestamp check on FILES passes.
    # But strictly, we should check timestamps. Let's just dump the URLs.
    
    HISTORY_VISITS=$(sqlite3 /tmp/history_check.db "SELECT url FROM urls WHERE url LIKE '%wikipedia.org%' ORDER BY last_visit_time DESC;" | tr '\n' ',' | sed 's/"/\\"/g')
    rm -f /tmp/history_check.db
fi

# Assemble JSON Result
# Note: Using python to robustly construct JSON to avoid bash quoting hell
python3 << PYEOF
import json
import os

result = {
    "task_start": $TASK_START,
    "files": {
        "schengen": $SCHENGEN_RESULT,
        "jet_lag": $JETLAG_RESULT,
        "travel_doc": $TRAVEL_DOC_RESULT
    },
    "history": {
        "wikipedia_visits": "$HISTORY_VISITS"
    },
    "screenshot_exists": os.path.exists("/tmp/task_final.png")
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json

echo "=== Export Complete ==="