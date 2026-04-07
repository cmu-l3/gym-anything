#!/bin/bash
echo "=== Exporting geography_capitals_memory_game task result ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Take final screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/memorize_geography_task_end.png" 2>/dev/null || true

TASK_START=$(cat /tmp/geography_task_start_ts 2>/dev/null || echo "0")
JOURNAL_DIR="/home/ga/.sugar/default/datastore"

JOURNAL_FOUND="false"
CORRECT_ACTIVITY_TYPE="false"
DATA_FILE_EXISTS="false"
DATA_SIZE=0
JOURNAL_ENTRY_PATH=""

echo "Searching for Journal entry created after $TASK_START..."

# Search the Journal for "South American Capitals"
if [ -d "$JOURNAL_DIR" ]; then
    while IFS= read -r -d '' TITLE_FILE; do
        if grep -qi "South American Capitals" "$TITLE_FILE" 2>/dev/null; then
            JOURNAL_FOUND="true"
            ENTRY_DIR=$(dirname "$(dirname "$TITLE_FILE")")
            JOURNAL_ENTRY_PATH="$ENTRY_DIR/data"
            
            # Check if it's actually a Memorize activity
            if grep -q "org.laptop.Memorize" "$ENTRY_DIR/metadata/activity" 2>/dev/null; then
                CORRECT_ACTIVITY_TYPE="true"
            fi
            echo "Found Journal entry at $ENTRY_DIR"
            break
        fi
    done < <(find "$JOURNAL_DIR" -name "title" -newer /tmp/geography_task_start_ts -print0 2>/dev/null)
    
    # Fallback: search ignoring timestamp (in case system clock drifted)
    if [ "$JOURNAL_FOUND" = "false" ]; then
        while IFS= read -r -d '' TITLE_FILE; do
            if grep -qi "South American Capitals" "$TITLE_FILE" 2>/dev/null; then
                JOURNAL_FOUND="true"
                ENTRY_DIR=$(dirname "$(dirname "$TITLE_FILE")")
                JOURNAL_ENTRY_PATH="$ENTRY_DIR/data"
                if grep -q "org.laptop.Memorize" "$ENTRY_DIR/metadata/activity" 2>/dev/null; then
                    CORRECT_ACTIVITY_TYPE="true"
                fi
                echo "Found Journal entry (ignoring timestamp) at $ENTRY_DIR"
                break
            fi
        done < <(find "$JOURNAL_DIR" -name "title" -print0 2>/dev/null)
    fi
fi

# Parse the XML data file with Python if found
if [ "$JOURNAL_FOUND" = "true" ] && [ -f "$JOURNAL_ENTRY_PATH" ]; then
    DATA_FILE_EXISTS="true"
    DATA_SIZE=$(stat --format=%s "$JOURNAL_ENTRY_PATH" 2>/dev/null || echo "0")
    echo "Game data file: $JOURNAL_ENTRY_PATH ($DATA_SIZE bytes)"
    
    python3 << 'PYEOF' > /tmp/geography_analysis.json 2>/dev/null || echo '{"error":"parse_failed"}' > /tmp/geography_analysis.json
import json
import re
import os
import sys

result = {
    "countries_found": [],
    "capitals_found": [],
    "error": None
}

data_file = sys.argv[1] if len(sys.argv) > 1 else None

try:
    if not data_file or not os.path.exists(data_file):
        raise FileNotFoundError("Data file not provided or does not exist")
        
    with open(data_file, 'r', errors='replace') as f:
        content = f.read().lower()
        
    expected_countries = ["argentina", "brazil", "chile", "colombia", "peru", "uruguay", "venezuela", "ecuador"]
    expected_capitals = ["buenos aires", "brasilia", "santiago", "bogota", "lima", "montevideo", "caracas", "quito"]
    
    for country in expected_countries:
        if country in content:
            result["countries_found"].append(country)
            
    for capital in expected_capitals:
        if capital in content:
            result["capitals_found"].append(capital)

except Exception as e:
    result["error"] = str(e)

print(json.dumps(result))
PYEOF
    # Run the script with the data file path
    python3 /tmp/geography_analysis.json "$JOURNAL_ENTRY_PATH" > /tmp/geography_analysis_out.json 2>/dev/null
    mv /tmp/geography_analysis_out.json /tmp/geography_analysis.json
else
    # Create empty analysis if file not found
    echo '{"countries_found": [], "capitals_found": [], "error": "file_not_found"}' > /tmp/geography_analysis.json
fi

# Compile final result JSON
cat > /tmp/geography_capitals_result.json << EOF
{
    "journal_found": $JOURNAL_FOUND,
    "correct_activity_type": $CORRECT_ACTIVITY_TYPE,
    "data_file_exists": $DATA_FILE_EXISTS,
    "data_size_bytes": $DATA_SIZE,
    "analysis": $(cat /tmp/geography_analysis.json)
}
EOF

chmod 666 /tmp/geography_capitals_result.json
echo "Result saved to /tmp/geography_capitals_result.json"
cat /tmp/geography_capitals_result.json
echo "=== Export complete ==="