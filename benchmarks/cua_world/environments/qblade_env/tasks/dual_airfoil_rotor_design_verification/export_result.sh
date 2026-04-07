#!/bin/bash
echo "=== Exporting dual_airfoil_rotor_design_verification results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# === 1. Check Project File ===
PROJECT_FILE="/home/ga/Documents/results/dual_airfoil_turbine.wpa"
PROJECT_EXISTS="false"
PROJECT_SIZE=0
PROJECT_CREATED_DURING_TASK="false"
PROJECT_IS_UNIQUE="false"
CONTAINS_0015="false"
CONTAINS_4412="false"
CONTAINS_BLADE="false"
CONTAINS_POLAR="false"

if [ -f "$PROJECT_FILE" ]; then
    PROJECT_EXISTS="true"
    PROJECT_SIZE=$(stat -c%s "$PROJECT_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$PROJECT_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PROJECT_CREATED_DURING_TASK="true"
    fi

    # Anti-copy check against sample projects
    PROJECT_HASH=$(md5sum "$PROJECT_FILE" 2>/dev/null | awk '{print $1}')
    if [ -f /tmp/sample_hashes.txt ]; then
        if ! grep -q "$PROJECT_HASH" /tmp/sample_hashes.txt 2>/dev/null; then
            PROJECT_IS_UNIQUE="true"
        fi
    else
        PROJECT_IS_UNIQUE="true"
    fi

    # Content checks (QBlade .wpa files contain readable text)
    if grep -q "0015" "$PROJECT_FILE" 2>/dev/null; then CONTAINS_0015="true"; fi
    if grep -q "4412" "$PROJECT_FILE" 2>/dev/null; then CONTAINS_4412="true"; fi
    if grep -qi "Blade\|Rotor" "$PROJECT_FILE" 2>/dev/null; then CONTAINS_BLADE="true"; fi
    if grep -qi "Polar\|XFoil" "$PROJECT_FILE" 2>/dev/null; then CONTAINS_POLAR="true"; fi
fi

# === 2. Check BEM Data File ===
BEM_FILE="/home/ga/Documents/results/cp_tsr_sweep.dat"
BEM_EXISTS="false"
BEM_DATA_LINES=0
BEM_HAS_HEADER="false"
BEM_CREATED_DURING_TASK="false"

if [ -f "$BEM_FILE" ]; then
    BEM_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$BEM_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        BEM_CREATED_DURING_TASK="true"
    fi

    # Count numeric data lines (lines starting with optional whitespace then a number)
    BEM_DATA_LINES=$(grep -cE '^[[:space:]]*-?[0-9]+\.?[0-9]*' "$BEM_FILE" 2>/dev/null || echo "0")

    # Check for header keywords
    if grep -qi "Cp\|TSR\|Power\|Lambda\|Coefficient" "$BEM_FILE" 2>/dev/null; then
        BEM_HAS_HEADER="true"
    fi
fi

# === 3. Check Performance Summary File ===
SUMMARY_FILE="/home/ga/Documents/results/performance_summary.txt"
SUMMARY_EXISTS="false"
SUMMARY_CREATED_DURING_TASK="false"
PARSED_CP="0"
PARSED_TSR="0"

if [ -f "$SUMMARY_FILE" ]; then
    SUMMARY_EXISTS="true"
    FILE_MTIME=$(stat -c%Y "$SUMMARY_FILE" 2>/dev/null || echo "0")

    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        SUMMARY_CREATED_DURING_TASK="true"
    fi

    # Try to extract Cp value (look for "Cp" followed by a decimal number)
    PARSED_CP=$(grep -i "Cp" "$SUMMARY_FILE" 2>/dev/null | grep -oE "[0-9]+\.[0-9]+" | head -1 || echo "0")
    if [ -z "$PARSED_CP" ]; then PARSED_CP="0"; fi

    # Try to extract TSR value (look for "TSR" followed by a number)
    PARSED_TSR=$(grep -i "TSR" "$SUMMARY_FILE" 2>/dev/null | grep -oE "[0-9]+\.?[0-9]*" | head -1 || echo "0")
    if [ -z "$PARSED_TSR" ]; then PARSED_TSR="0"; fi
fi

# === 4. Check QBlade State ===
APP_RUNNING=$(is_qblade_running)

# === 5. Write Result JSON ===
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_exists": $PROJECT_EXISTS,
    "project_size_bytes": $PROJECT_SIZE,
    "project_created_during_task": $PROJECT_CREATED_DURING_TASK,
    "project_is_unique": $PROJECT_IS_UNIQUE,
    "contains_0015": $CONTAINS_0015,
    "contains_4412": $CONTAINS_4412,
    "contains_blade_def": $CONTAINS_BLADE,
    "contains_polar_data": $CONTAINS_POLAR,
    "bem_exists": $BEM_EXISTS,
    "bem_data_lines": $BEM_DATA_LINES,
    "bem_has_header": $BEM_HAS_HEADER,
    "bem_created_during_task": $BEM_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "summary_created_during_task": $SUMMARY_CREATED_DURING_TASK,
    "parsed_cp_max": "$PARSED_CP",
    "parsed_optimal_tsr": "$PARSED_TSR",
    "app_running": $([ "$APP_RUNNING" -gt 0 ] && echo "true" || echo "false"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

write_result_json "$(cat "$TEMP_JSON")" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="
