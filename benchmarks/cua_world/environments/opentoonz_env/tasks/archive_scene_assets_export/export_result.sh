#!/bin/bash
echo "=== Exporting archive_scene_assets_export result ==="

# Define paths
OUTPUT_DIR="/home/ga/OpenToonz/output/handoff_package"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Analyze File System State
SCENE_FOUND="false"
ASSET_FOUND="false"
FILES_NEW="false"
SCENE_FILE_PATH=""
ASSET_FILE_PATH=""

# Check for .tnz file
SCENE_FILE=$(find "$OUTPUT_DIR" -name "*.tnz" | head -n 1)
if [ -n "$SCENE_FILE" ]; then
    SCENE_FOUND="true"
    SCENE_FILE_PATH="$SCENE_FILE"
    
    # Check timestamp
    SCENE_MTIME=$(stat -c %Y "$SCENE_FILE")
    if [ "$SCENE_MTIME" -gt "$TASK_START" ]; then
        FILES_NEW="true"
    fi
fi

# Check for asset files (.pli or .tlv)
# The sample dwanko_run usually uses .pli (vector) levels
ASSET_FILE=$(find "$OUTPUT_DIR" -name "*.pli" -o -name "*.tlv" | head -n 1)
if [ -n "$ASSET_FILE" ]; then
    ASSET_FOUND="true"
    ASSET_FILE_PATH="$ASSET_FILE"
    
    # Check timestamp
    ASSET_MTIME=$(stat -c %Y "$ASSET_FILE")
    if [ "$ASSET_MTIME" -gt "$TASK_START" ]; then
        # If scene was old but asset is new, that's still valid work
        FILES_NEW="true"
    fi
fi

# 3. Analyze Scene Content (Path References)
# We need to verify that the exported scene references the local asset, 
# not the original one in /samples/
PATH_IS_RELATIVE="false"
PATH_IS_LOCAL_ABS="false"
ORIGINAL_PATH_REF="false"

if [ "$SCENE_FOUND" = "true" ]; then
    # TNZ files are XML. We look for <levelPath> tags.
    # We want to see if they contain "dwanko_run.pli" without the original path
    
    # Read level paths
    LEVEL_PATHS=$(grep "<levelPath>" "$SCENE_FILE" || true)
    
    if echo "$LEVEL_PATHS" | grep -q "samples/dwanko_run.pli"; then
        ORIGINAL_PATH_REF="true"
    fi
    
    # Check for simple relative path (ideal) e.g., <levelPath>dwanko_run.pli</levelPath>
    # or <levelPath>inputs/dwanko_run.pli</levelPath> if OT created a subdir
    if echo "$LEVEL_PATHS" | grep -q ">dwanko_run.pli<" || echo "$LEVEL_PATHS" | grep -q ">[^/]*dwanko_run.pli<"; then
        PATH_IS_RELATIVE="true"
    fi
    
    # Check for absolute path to the NEW directory
    if echo "$LEVEL_PATHS" | grep -q "$OUTPUT_DIR"; then
        PATH_IS_LOCAL_ABS="true"
    fi
fi

# 4. JSON Export
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "scene_found": $SCENE_FOUND,
    "asset_found": $ASSET_FOUND,
    "files_created_during_task": $FILES_NEW,
    "path_is_relative": $PATH_IS_RELATIVE,
    "path_is_local_absolute": $PATH_IS_LOCAL_ABS,
    "original_path_reference": $ORIGINAL_PATH_REF,
    "scene_path": "$SCENE_FILE_PATH",
    "asset_path": "$ASSET_FILE_PATH",
    "output_dir_exists": $([ -d "$OUTPUT_DIR" ] && echo "true" || echo "false")
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="