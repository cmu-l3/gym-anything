#!/bin/bash
echo "=== Exporting compare_bem_llt_performance results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# --- 1. Check Project File (.wpa) ---
PROJECT_PATH="/home/ga/Documents/projects/comparison_study.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
HAS_LLT_DATA="false"
HAS_BEM_DATA="false"

if [ -f "$PROJECT_PATH" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_PATH")
    
    # Check modification time
    PROJECT_MTIME=$(stat -c%Y "$PROJECT_PATH")
    if [ "$PROJECT_MTIME" -lt "$TASK_START" ]; then
        PROJECT_EXISTS="false_stale" # File exists but is old
    fi

    # Inspect file content for Simulation Objects
    # QBlade .wpa files are typically text/xml mixed. We look for simulation definition tags.
    # LLT simulations often have tags like "QLLT", "LiftingLine", "Vortex"
    if grep -aqE "LLT|LiftingLine|Vortex|QLLT" "$PROJECT_PATH"; then
        HAS_LLT_DATA="true"
    fi
    
    # BEM simulations
    if grep -aqE "BEM|BladeElement|QBem" "$PROJECT_PATH"; then
        HAS_BEM_DATA="true"
    fi
fi

# --- 2. Check Report File (.txt) ---
REPORT_PATH="/home/ga/Documents/projects/bem_vs_llt.txt"
REPORT_EXISTS="false"
REPORT_CONTENT=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 500) # Read first 500 chars
fi

# --- 3. Check Wake Screenshot ---
# The task asks the agent to take a screenshot.
# We look for image files created in the project folder during the task window.
SCREENSHOT_FOUND="false"
SCREENSHOT_PATH=""
SCREENSHOT_COUNT=$(find /home/ga/Documents/projects -name "*.png" -newermt "@$TASK_START" 2>/dev/null | wc -l)

if [ "$SCREENSHOT_COUNT" -gt 0 ]; then
    SCREENSHOT_FOUND="true"
    # Pick the largest one as the likely candidate
    SCREENSHOT_PATH=$(find /home/ga/Documents/projects -name "*.png" -newermt "@$TASK_START" -type f -printf "%s %p\n" | sort -nr | head -1 | awk '{print $2}')
fi

# --- 4. Capture Final System Screenshot (Trajectory End) ---
take_screenshot /tmp/task_final.png

# --- 5. Generate JSON Result ---
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": "$PROJECT_EXISTS",
    "project_size": $PROJECT_SIZE,
    "has_llt_data": $HAS_LLT_DATA,
    "has_bem_data": $HAS_BEM_DATA,
    "report_exists": $REPORT_EXISTS,
    "report_content": "$(echo "$REPORT_CONTENT" | sed 's/"/\\"/g' | tr -d '\n')",
    "agent_screenshot_found": $SCREENSHOT_FOUND,
    "agent_screenshot_path": "$SCREENSHOT_PATH"
}
EOF

# Move to final location safely
write_result_json "$(cat $TEMP_JSON)" "/tmp/task_result.json"
rm "$TEMP_JSON"

echo "=== Export complete ==="