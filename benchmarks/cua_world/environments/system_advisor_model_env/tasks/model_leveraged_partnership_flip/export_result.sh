#!/bin/bash
echo "=== Exporting task result ==="

# Take final screenshot
DISPLAY=:1 import -window root /tmp/task_end.png 2>/dev/null || true

TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")
PY_FILE="/home/ga/Documents/SAM_Projects/levpartflip_model.py"
JSON_FILE="/home/ga/Documents/SAM_Projects/levpartflip_results.json"

PY_EXISTS="false"
PY_MODIFIED="false"
PYSAM_IMPORTED="false"
JSON_EXISTS="false"
JSON_MODIFIED="false"

# Check Python script
if [ -f "$PY_FILE" ]; then
    PY_EXISTS="true"
    PY_MTIME=$(stat -c%Y "$PY_FILE" 2>/dev/null || echo "0")
    if [ "$PY_MTIME" -gt "$TASK_START" ]; then
        PY_MODIFIED="true"
    fi
    # Check if the python script imports PySAM
    if grep -qiE "import pysam|from pysam|pvwatts|levpartflip" "$PY_FILE"; then
        PYSAM_IMPORTED="true"
    fi
fi

# Check JSON results
if [ -f "$JSON_FILE" ]; then
    JSON_EXISTS="true"
    JSON_MTIME=$(stat -c%Y "$JSON_FILE" 2>/dev/null || echo "0")
    if [ "$JSON_MTIME" -gt "$TASK_START" ]; then
        JSON_MODIFIED="true"
    fi
fi

# Export minimal summary for the verifier
# (The verifier will use copy_from_env to parse the actual JSON output)
cat > /tmp/task_result.json << EOF
{
    "py_exists": $PY_EXISTS,
    "py_modified": $PY_MODIFIED,
    "pysam_imported": $PYSAM_IMPORTED,
    "json_exists": $JSON_EXISTS,
    "json_modified": $JSON_MODIFIED,
    "task_start": $TASK_START
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="