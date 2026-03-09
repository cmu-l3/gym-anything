#!/bin/bash
echo "=== Exporting resolve_compiler_warnings result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

PROJECT_SRC="/home/ga/eclipse-workspace/DataUtils/src"
WORKSPACE_SETTINGS="/home/ga/eclipse-workspace/.metadata/.plugins/org.eclipse.core.runtime/.settings"
PREFS_FILE="$WORKSPACE_SETTINGS/org.eclipse.jdt.core.prefs"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Check if project was imported
PROJECT_IMPORTED="false"
if [ -d "$PROJECT_SRC" ]; then
    PROJECT_IMPORTED="true"
fi

# 3. Check for file modifications (compare current checksums to initial)
FILES_MODIFIED="false"
MODIFIED_COUNT=0
if [ "$PROJECT_IMPORTED" = "true" ]; then
    find "$PROJECT_SRC" -name "*.java" -type f -exec sha256sum {} \; | sort > /tmp/final_checksums.txt
    
    # Compare with initial checksums (from setup_task.sh)
    # Note: Paths will differ (/project-sources/ vs /eclipse-workspace/), so compare hashes only
    INITIAL_HASHES=$(cat /tmp/initial_checksums.txt | awk '{print $1}' | sort)
    FINAL_HASHES=$(cat /tmp/final_checksums.txt | awk '{print $1}' | sort)
    
    if [ "$INITIAL_HASHES" != "$FINAL_HASHES" ]; then
        FILES_MODIFIED="true"
        # Count how many files changed
        # This is a rough approximation
        MODIFIED_COUNT=$(comm -3 <(echo "$INITIAL_HASHES") <(echo "$FINAL_HASHES") | wc -l)
        # Divide by 2 because comm outputs lines from both files
        MODIFIED_COUNT=$((MODIFIED_COUNT / 2))
    fi
fi

# 4. Check Eclipse Preferences for Compiler Settings
# We look for the workspace-level preferences since the task asks to change Window > Preferences
PREFS_CORRECT="false"
RAW_TYPE_SETTING="ignore"
UNUSED_IMPORT_SETTING="ignore"

if [ -f "$PREFS_FILE" ]; then
    RAW_TYPE_SETTING=$(grep "org.eclipse.jdt.core.compiler.problem.rawTypeReference" "$PREFS_FILE" | cut -d= -f2 || echo "ignore")
    UNUSED_IMPORT_SETTING=$(grep "org.eclipse.jdt.core.compiler.problem.unusedImport" "$PREFS_FILE" | cut -d= -f2 || echo "ignore")
    
    if [ "$RAW_TYPE_SETTING" = "error" ] && [ "$UNUSED_IMPORT_SETTING" = "error" ]; then
        PREFS_CORRECT="true"
    fi
fi

# 5. Run headless Java compiler check to verify code quality
# We copy sources to a temp dir to compile them cleanly
TEMP_BUILD_DIR=$(mktemp -d)
COMPILE_SUCCESS="false"
WARNING_COUNT=0
ERROR_COUNT=0

if [ "$PROJECT_IMPORTED" = "true" ]; then
    # Copy sources
    cp -r "$PROJECT_SRC" "$TEMP_BUILD_DIR/src"
    
    # Attempt compilation with -Xlint:all
    mkdir -p "$TEMP_BUILD_DIR/bin"
    
    # Capture stderr to log
    javac -d "$TEMP_BUILD_DIR/bin" -sourcepath "$TEMP_BUILD_DIR/src" -Xlint:all $(find "$TEMP_BUILD_DIR/src" -name "*.java") > "$TEMP_BUILD_DIR/compile.log" 2>&1
    COMPILE_EXIT_CODE=$?
    
    if [ $COMPILE_EXIT_CODE -eq 0 ]; then
        COMPILE_SUCCESS="true"
    fi
    
    # Count warnings/errors in the log
    WARNING_COUNT=$(grep -c "warning:" "$TEMP_BUILD_DIR/compile.log" || echo 0)
    ERROR_COUNT=$(grep -c "error:" "$TEMP_BUILD_DIR/compile.log" || echo 0)
    
    # Save compilation log for verification
    cat "$TEMP_BUILD_DIR/compile.log" > /tmp/compilation_check.log
fi

# 6. Clean up
rm -rf "$TEMP_BUILD_DIR"

# 7. Create JSON result
# Escape strings for JSON
RAW_TYPE_ESC=$(echo "$RAW_TYPE_SETTING" | sed 's/"/\\"/g')
UNUSED_IMPORT_ESC=$(echo "$UNUSED_IMPORT_SETTING" | sed 's/"/\\"/g')
COMPILATION_LOG_CONTENT=$(cat /tmp/compilation_check.log 2>/dev/null | head -c 2000 | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))')

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "project_imported": $PROJECT_IMPORTED,
    "files_modified": $FILES_MODIFIED,
    "modified_file_count": $MODIFIED_COUNT,
    "prefs_correct": $PREFS_CORRECT,
    "prefs_raw_type": "$RAW_TYPE_ESC",
    "prefs_unused_import": "$UNUSED_IMPORT_ESC",
    "compile_success": $COMPILE_SUCCESS,
    "warning_count": $WARNING_COUNT,
    "error_count": $ERROR_COUNT,
    "compilation_log": $COMPILATION_LOG_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Export complete. Result:"
cat /tmp/task_result.json