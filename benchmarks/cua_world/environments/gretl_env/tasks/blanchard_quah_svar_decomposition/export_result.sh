#!/bin/bash
echo "=== Exporting Blanchard-Quah SVAR results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_DIR="/home/ga/Documents/gretl_output"
SCRIPT_PATH="$OUTPUT_DIR/bq_svar.inp"
REPORT_PATH="$OUTPUT_DIR/bq_results.txt"

# =====================================================================
# Helper: check a single file's existence, size, freshness
# =====================================================================
check_file() {
    local fpath="$1"
    if [ -f "$fpath" ]; then
        local mtime=$(stat -c %Y "$fpath" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$fpath" 2>/dev/null || echo "0")
        local fresh="false"
        if [ "$mtime" -ge "$TASK_START" ]; then
            fresh="true"
        fi
        echo "{\"exists\": true, \"size\": $size, \"fresh\": $fresh, \"path\": \"$fpath\"}"
    else
        echo "{\"exists\": false, \"size\": 0, \"fresh\": false, \"path\": \"$fpath\"}"
    fi
}

# =====================================================================
# Check primary output files
# =====================================================================
SCRIPT_INFO=$(check_file "$SCRIPT_PATH")
REPORT_INFO=$(check_file "$REPORT_PATH")

# =====================================================================
# Count IRF PNG files in output directory
# =====================================================================
IRF_PNG_COUNT=0
IRF_PNG_LIST="[]"
if [ -d "$OUTPUT_DIR" ]; then
    # Find PNG files that could be IRF plots (created during task)
    PNG_FILES=""
    for png in "$OUTPUT_DIR"/*.png; do
        if [ -f "$png" ]; then
            png_mtime=$(stat -c %Y "$png" 2>/dev/null || echo "0")
            if [ "$png_mtime" -ge "$TASK_START" ]; then
                IRF_PNG_COUNT=$((IRF_PNG_COUNT + 1))
                PNG_FILES="$PNG_FILES\"$(basename "$png")\","
            fi
        fi
    done
    # Build JSON array (strip trailing comma)
    if [ -n "$PNG_FILES" ]; then
        PNG_FILES="${PNG_FILES%,}"
        IRF_PNG_LIST="[$PNG_FILES]"
    fi
fi

# =====================================================================
# Read report content (first 5000 chars for verification)
# =====================================================================
REPORT_CONTENT='""'
if [ -f "$REPORT_PATH" ]; then
    REPORT_CONTENT=$(head -c 5000 "$REPORT_PATH" | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# =====================================================================
# Read script content (first 3000 chars for verification)
# =====================================================================
SCRIPT_CONTENT='""'
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_CONTENT=$(head -c 3000 "$SCRIPT_PATH" | python3 -c "
import sys, json
content = sys.stdin.read()
print(json.dumps(content))
" 2>/dev/null || echo '""')
fi

# =====================================================================
# Check if gretl is still running
# =====================================================================
APP_RUNNING="false"
if pgrep -f "gretl" > /dev/null 2>&1; then
    APP_RUNNING="true"
fi

# =====================================================================
# Take final screenshot
# =====================================================================
DISPLAY="${DISPLAY:-:1}" scrot /tmp/task_final.png 2>/dev/null || true

# =====================================================================
# Bundle results into JSON
# =====================================================================
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "script_file": $SCRIPT_INFO,
    "report_file": $REPORT_INFO,
    "irf_png_count": $IRF_PNG_COUNT,
    "irf_png_files": $IRF_PNG_LIST,
    "report_content": $REPORT_CONTENT,
    "script_content": $SCRIPT_CONTENT,
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="
