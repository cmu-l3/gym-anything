#!/bin/bash
echo "=== Exporting locate_database_file result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Parse Agent's Report
REPORT_PATH="/home/ga/lobby_track_db_report.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""
AGENT_PATH=""
AGENT_SIZE=""
AGENT_FORMAT=""
REPORT_TIMESTAMP=0

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH")
    REPORT_TIMESTAMP=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    
    # Parse lines
    AGENT_PATH=$(grep "^DATABASE_PATH=" "$REPORT_PATH" | cut -d'=' -f2 | tr -d '\r')
    AGENT_SIZE=$(grep "^DATABASE_SIZE_BYTES=" "$REPORT_PATH" | cut -d'=' -f2 | tr -d '\r')
    AGENT_FORMAT=$(grep "^DATABASE_FORMAT=" "$REPORT_PATH" | cut -d'=' -f2 | tr -d '\r')
fi

# 2. Determine Ground Truth (Find the actual database)
# Lobby Track usually uses .mdb (Access) or .sdf (SQL CE)
# We look for the largest database file in the Wine prefix that contains "Lobby" or is in the Jolly directory
echo "Searching for ground truth database..."

# Find candidate files
CANDIDATES=$(find /home/ga/.wine/drive_c -type f \( -iname "*.mdb" -o -iname "*.sdf" -o -iname "*.accdb" \) -not -path "*/Windows/*" -not -path "*/Temp/*" -printf "%s %p\n" | sort -nr | head -5)

# Pick the most likely one (usually the largest one in a Jolly folder)
GROUND_TRUTH_PATH=""
GROUND_TRUTH_SIZE="0"

# First pass: Look for "Lobby" or "Jolly" in path
while read -r size path; do
    if [[ "$path" == *"Lobby"* ]] || [[ "$path" == *"Jolly"* ]]; then
        GROUND_TRUTH_PATH="$path"
        GROUND_TRUTH_SIZE="$size"
        break
    fi
done <<< "$CANDIDATES"

# Fallback: Just take the largest DB file found if none matched above
if [ -z "$GROUND_TRUTH_PATH" ] && [ -n "$CANDIDATES" ]; then
    read -r GROUND_TRUTH_SIZE GROUND_TRUTH_PATH <<< $(echo "$CANDIDATES" | head -1)
fi

echo "Ground Truth DB: $GROUND_TRUTH_PATH ($GROUND_TRUTH_SIZE bytes)"

# 3. Verify Agent's File Path Validity
AGENT_PATH_VALID="false"
AGENT_PATH_IS_DB="false"
REAL_SIZE_OF_AGENT_PATH="0"

if [ -n "$AGENT_PATH" ]; then
    if [ -f "$AGENT_PATH" ]; then
        AGENT_PATH_VALID="true"
        REAL_SIZE_OF_AGENT_PATH=$(stat -c %s "$AGENT_PATH" 2>/dev/null || echo "0")
        
        # Check if it looks like a DB
        if [[ "$AGENT_PATH" == *".mdb" ]] || [[ "$AGENT_PATH" == *".sdf" ]] || [[ "$AGENT_PATH" == *".accdb" ]] || [[ "$AGENT_PATH" == *".db" ]]; then
            AGENT_PATH_IS_DB="true"
        fi
    fi
fi

# 4. Check App State
APP_RUNNING="false"
if pgrep -f "LobbyTrack" > /dev/null || pgrep -f "Lobby" > /dev/null; then
    APP_RUNNING="true"
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "report_exists": $REPORT_EXISTS,
    "report_timestamp": $REPORT_TIMESTAMP,
    "task_start_time": $(cat /tmp/locate_database_file_start_time 2>/dev/null || echo "0"),
    "agent_reported": {
        "path": "$AGENT_PATH",
        "size": "$AGENT_SIZE",
        "format": "$AGENT_FORMAT"
    },
    "ground_truth": {
        "path": "$GROUND_TRUTH_PATH",
        "size": $GROUND_TRUTH_SIZE
    },
    "validation": {
        "path_exists": $AGENT_PATH_VALID,
        "path_is_db_extension": $AGENT_PATH_IS_DB,
        "actual_size_of_agent_path": $REAL_SIZE_OF_AGENT_PATH
    },
    "app_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save result
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"