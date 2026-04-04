#!/bin/bash
set -e
echo "=== Exporting Reproject View CRS Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final state
take_screenshot /tmp/task_final_state.png

# 2. Gather file paths and times
OUTPUT_PROJECT="/home/ga/gvsig_data/projects/mercator_project.gvsproj"
BASE_PROJECT="/home/ga/gvsig_data/projects/countries_base.gvsproj"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check output file status
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CREATED_DURING_TASK="false"
FILE_DIFFERS_FROM_BASE="false"
CRS_FOUND="false"
CRS_MATCH_DETAIL=""

if [ -f "$OUTPUT_PROJECT" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$OUTPUT_PROJECT")
    FILE_MTIME=$(stat -c %Y "$OUTPUT_PROJECT")
    
    # Check timestamp
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check if identical to base (anti-gaming: did they just Save As without changing anything?)
    # Calculate hash of output
    OUTPUT_HASH=$(md5sum "$OUTPUT_PROJECT" | awk '{print $1}')
    BASE_HASH=$(cat /tmp/base_project_hash.txt 2>/dev/null || echo "none")
    
    if [ "$OUTPUT_HASH" != "$BASE_HASH" ]; then
        FILE_DIFFERS_FROM_BASE="true"
    fi

    # 4. Content Analysis for CRS 3857
    # gvSIG projects are often ZIPs or XMLs. We search for the EPSG code.
    # We look for "3857", "Pseudo-Mercator", "Web Mercator"
    
    # Try searching as plain text first (works for uncompressed XML or if strings works)
    # Using 'strings' is robust for binary/zipped files
    STRINGS_CONTENT=$(strings "$OUTPUT_PROJECT" | grep -i "3857\|Pseudo[-_ ]Mercator\|Web[-_ ]Mercator\|Google[-_ ]Mercator")
    
    if [ -n "$STRINGS_CONTENT" ]; then
        CRS_FOUND="true"
        # store first match for log
        CRS_MATCH_DETAIL=$(echo "$STRINGS_CONTENT" | head -1 | tr -d '"\\') 
    else
        # Fallback: if it is a zip, try to list/cat content
        if unzip -t "$OUTPUT_PROJECT" >/dev/null 2>&1; then
            # It's a zip. Search inside.
            ZIP_MATCH=$(unzip -p "$OUTPUT_PROJECT" | grep -i "3857\|Pseudo[-_ ]Mercator" | head -1)
            if [ -n "$ZIP_MATCH" ]; then
                CRS_FOUND="true"
                CRS_MATCH_DETAIL=$(echo "$ZIP_MATCH" | tr -d '"\\')
            fi
        fi
    fi
fi

# 5. Check if gvSIG is still running
APP_RUNNING="false"
if pgrep -f "gvSIG" > /dev/null; then
    APP_RUNNING="true"
fi

# 6. Create JSON result
# Use a temp file to avoid permission issues, then move
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_path": "$OUTPUT_PROJECT",
    "file_size_bytes": $FILE_SIZE,
    "file_mtime": $FILE_MTIME,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_differs_from_base": $FILE_DIFFERS_FROM_BASE,
    "crs_reference_found": $CRS_FOUND,
    "crs_match_detail": "$CRS_MATCH_DETAIL",
    "app_running": $APP_RUNNING,
    "final_screenshot": "/tmp/task_final_state.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json