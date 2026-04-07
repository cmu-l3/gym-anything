#!/bin/bash
echo "=== Exporting analyze_part_mass result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Load start variables
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OLD_GROUPS=$(cat /tmp/initial_group_count.txt 2>/dev/null || echo "0")

# Paths
EXTRUDED_FILE="/home/ga/Documents/SolveSpace/side_extruded.slvs"
REPORT_FILE="/home/ga/Documents/SolveSpace/mass_report.txt"

# 1. Check Extruded CAD File
EXTRUDED_EXISTS="false"
EXTRUDED_MTIME=0
NEW_GROUPS=0

if [ -f "$EXTRUDED_FILE" ]; then
    EXTRUDED_EXISTS="true"
    EXTRUDED_MTIME=$(stat -c %Y "$EXTRUDED_FILE" 2>/dev/null || echo "0")
    NEW_GROUPS=$(grep -c "Group.type" "$EXTRUDED_FILE" 2>/dev/null || echo "0")
fi

# 2. Check Text Report File
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_CONTENT_JSON="null"

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE" 2>/dev/null || echo "0")
    # Read up to 1000 chars and safely JSON-encode it
    REPORT_CONTENT_JSON=$(cat "$REPORT_FILE" | head -c 1000 | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "extruded_exists": $EXTRUDED_EXISTS,
    "extruded_mtime": $EXTRUDED_MTIME,
    "old_groups": $OLD_GROUPS,
    "new_groups": $NEW_GROUPS,
    "report_exists": $REPORT_EXISTS,
    "report_mtime": $REPORT_MTIME,
    "report_content": $REPORT_CONTENT_JSON
}
EOF

# Make result accessible to verifier
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="