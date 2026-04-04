#!/bin/bash
# Export script for Translate Maternal Health Metadata task

echo "=== Exporting Translation Result ==="

source /workspace/scripts/task_utils.sh

if ! type dhis2_api &>/dev/null; then
    dhis2_api() {
        curl -s -u admin:district "http://localhost:8080/api/$1"
    }
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START_ISO=$(cat /tmp/task_start_iso 2>/dev/null || echo "2020-01-01T00:00:00+0000")

# 1. Check for the log file
LOG_FILE="/home/ga/Desktop/translation_log.txt"
LOG_EXISTS="false"
LOG_CONTENT=""
LOG_SIZE="0"

if [ -f "$LOG_FILE" ]; then
    LOG_EXISTS="true"
    LOG_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo "0")
    # Read first 500 chars safely
    LOG_CONTENT=$(head -c 500 "$LOG_FILE" | sed 's/"/\\"/g' | tr '\n' ' ')
fi

# 2. Query DHIS2 API for ANC data elements and their translations
# We fetch all data elements with "ANC" in the name to ensure we catch the targets
echo "Querying DHIS2 metadata..."
API_RESPONSE=$(dhis2_api "dataElements?filter=name:ilike:ANC&fields=id,name,lastUpdated,translations&paging=false" 2>/dev/null)

# 3. Parse API response with Python to extract relevant status
# This simplifies the logic in the bash script and handles JSON robustly
PYTHON_PARSER=$(cat << 'PY_EOF'
import json, sys, re

try:
    data = json.load(sys.stdin)
    log_exists = sys.argv[1] == "true"
    log_content = sys.argv[2]
    
    data_elements = data.get("dataElements", [])
    
    # Target names to look for (normalized lower case for matching)
    targets = [
        "anc 1st visit", 
        "anc 2nd visit", 
        "anc 3rd visit", 
        "anc 4th visit", 
        "anc ipt 1st dose"
    ]
    
    results = {
        "log_file_exists": log_exists,
        "log_content_sample": log_content,
        "elements_found": [],
        "targets_translated_count": 0,
        "cpn_term_used_count": 0
    }
    
    for de in data_elements:
        name = de.get("name", "")
        # Check if this is one of our targets
        is_target = False
        for t in targets:
            # Flexible matching: allows "ANC 1st visit" or "ANC 1st Visit" etc.
            if t in name.lower():
                is_target = True
                break
        
        # If it's not a target, we skip detailed processing to keep result small
        if not is_target:
            continue
            
        translations = de.get("translations", [])
        fr_translation = None
        
        for t in translations:
            if t.get("locale") == "fr" and t.get("property") == "NAME":
                fr_translation = t.get("value", "")
                break
        
        if fr_translation:
            results["targets_translated_count"] += 1
            if "CPN" in fr_translation:
                results["cpn_term_used_count"] += 1
        
        results["elements_found"].append({
            "name": name,
            "id": de.get("id"),
            "lastUpdated": de.get("lastUpdated"),
            "french_translation": fr_translation
        })
        
    print(json.dumps(results))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PY_EOF
)

# Run the parser
# Pass log file status as args
PARSED_RESULT=$(echo "$API_RESPONSE" | python3 -c "$PYTHON_PARSER" "$LOG_EXISTS" "$LOG_CONTENT")

# Save final result
echo "$PARSED_RESULT" > /tmp/translation_result.json
chmod 666 /tmp/translation_result.json 2>/dev/null || true

echo "Export result:"
cat /tmp/translation_result.json
echo ""
echo "=== Export Complete ==="