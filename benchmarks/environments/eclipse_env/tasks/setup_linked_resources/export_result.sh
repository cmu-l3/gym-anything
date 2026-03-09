#!/bin/bash
echo "=== Exporting setup_linked_resources result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/eclipse-workspace/TreatmentPlanner"
PROJECT_FILE="$PROJECT_DIR/.project"
OUTPUT_FILE="$PROJECT_DIR/protocol_index.txt"
SOURCE_FILE="$PROJECT_DIR/src/com/hospital/planning/ProtocolIndexer.java"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check .project file content (for Linked Resources)
PROJECT_FILE_EXISTS="false"
PROJECT_CONTENT=""
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_FILE_EXISTS="true"
    # Read file content
    PROJECT_CONTENT=$(cat "$PROJECT_FILE")
fi

# 2. Check output file (protocol_index.txt)
OUTPUT_EXISTS="false"
OUTPUT_CONTENT=""
OUTPUT_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_FILE" ]; then
    OUTPUT_EXISTS="true"
    OUTPUT_CONTENT=$(cat "$OUTPUT_FILE")
    
    # Check modification time
    FILE_MTIME=$(stat -c %Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        OUTPUT_CREATED_DURING_TASK="true"
    fi
fi

# 3. Check Source Code
SOURCE_EXISTS="false"
if [ -f "$SOURCE_FILE" ]; then
    SOURCE_EXISTS="true"
fi

# 4. Check Linked Folder existence in filesystem (should NOT exist as a real folder in workspace)
# If the user copied the files, 'protocols' would be a real directory.
# If linked, it appears in Eclipse but on disk it's just metadata in .project (usually).
# However, Eclipse doesn't create a symlink on disk for linked resources by default, 
# it handles it internally. So 'protocols' should NOT exist in $PROJECT_DIR on disk.
# NOTE: If the user used symlinks (ln -s), that might appear as a file/dir.
REAL_FOLDER_EXISTS="false"
IS_SYMLINK="false"
if [ -e "$PROJECT_DIR/protocols" ]; then
    REAL_FOLDER_EXISTS="true"
    if [ -L "$PROJECT_DIR/protocols" ]; then
        IS_SYMLINK="true"
    fi
fi

# Escape content for JSON
PROJECT_CONTENT_ESC=$(echo "$PROJECT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')
OUTPUT_CONTENT_ESC=$(echo "$OUTPUT_CONTENT" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read()))" 2>/dev/null || echo '""')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_file_exists": $PROJECT_FILE_EXISTS,
    "project_file_content": $PROJECT_CONTENT_ESC,
    "output_file_exists": $OUTPUT_EXISTS,
    "output_file_content": $OUTPUT_CONTENT_ESC,
    "output_created_during_task": $OUTPUT_CREATED_DURING_TASK,
    "source_file_exists": $SOURCE_EXISTS,
    "real_folder_exists_in_workspace": $REAL_FOLDER_EXISTS,
    "is_symlink": $IS_SYMLINK
}
EOF

write_json_result "$TEMP_JSON" /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="