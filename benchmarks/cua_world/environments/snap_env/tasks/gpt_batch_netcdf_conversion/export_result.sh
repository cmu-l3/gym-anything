#!/bin/bash
echo "=== Exporting gpt_batch_netcdf_conversion result ==="

# Record baseline for timestamps
TASK_START=$(cat /tmp/task_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

SCRIPT_PATH="/home/ga/batch_convert.sh"
OUT_DIR="/home/ga/snap_exports/netcdf_batch"

# Initialization
SCRIPT_EXISTS="false"
IS_EXECUTABLE="false"
HAS_LOOP="false"
HAS_GPT="false"

# Script analysis
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    [ -x "$SCRIPT_PATH" ] && IS_EXECUTABLE="true"
    
    # Check for basic automation logic (bash iteration tools)
    if grep -qE "for|while|find|xargs|ls" "$SCRIPT_PATH"; then
        HAS_LOOP="true"
    fi
    
    # Check for SNAP GPT invocation
    if grep -qi "gpt" "$SCRIPT_PATH"; then
        HAS_GPT="true"
    fi
fi

# Output data analysis
NC_COUNT=0
VALID_NC_COUNT=0
NEW_FILES_COUNT=0

if [ -d "$OUT_DIR" ]; then
    # Iterate over expected .nc files
    for f in "$OUT_DIR"/*.nc; do
        if [ -f "$f" ]; then
            NC_COUNT=$((NC_COUNT + 1))
            
            # Anti-gaming: Ensure file was modified after task started
            MTIME=$(stat -c %Y "$f" 2>/dev/null || echo "0")
            if [ "$MTIME" -gt "$TASK_START" ]; then
                NEW_FILES_COUNT=$((NEW_FILES_COUNT + 1))
            fi
            
            # File format authenticity: Read magic bytes
            # NetCDF3 (CDF) starts with 434446, NetCDF4 (HDF5) starts with 89484446
            MAGIC=$(head -c 4 "$f" | xxd -p)
            if echo "$MAGIC" | grep -qiE "434446|89484446"; then
                VALID_NC_COUNT=$((VALID_NC_COUNT + 1))
            fi
        fi
    done
fi

# Generate JSON payload for the verifier script
TEMP_JSON=$(mktemp)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "script_exists": $SCRIPT_EXISTS,
    "is_executable": $IS_EXECUTABLE,
    "has_loop": $HAS_LOOP,
    "has_gpt": $HAS_GPT,
    "nc_count": $NC_COUNT,
    "valid_nc_count": $VALID_NC_COUNT,
    "new_files_count": $NEW_FILES_COUNT,
    "out_dir_exists": $([ -d "$OUT_DIR" ] && echo "true" || echo "false")
}
EOF

# Move payload to standardized location
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="