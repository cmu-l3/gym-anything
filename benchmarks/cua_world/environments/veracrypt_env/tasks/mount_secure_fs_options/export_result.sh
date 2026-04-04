#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting mount_secure_fs_options result ==="

MOUNT_POINT="/home/ga/MountPoints/secure_data"
REPORT_PATH="/home/ga/Documents/mount_security_report.txt"

# 1. Check if mounted
IS_MOUNTED="false"
if mountpoint -q "$MOUNT_POINT"; then
    IS_MOUNTED="true"
fi

# 2. Get mount options from /proc/mounts
MOUNT_OPTIONS=""
if [ "$IS_MOUNTED" = "true" ]; then
    # grep the mount point, get the options string (4th field)
    MOUNT_OPTIONS=$(grep "$MOUNT_POINT" /proc/mounts | head -1 | awk '{print $4}')
fi

# 3. Test noexec active enforcement
NOEXEC_ACTIVE="false"
TEST_SCRIPT_CREATED="false"
TEST_OUTPUT=""

if [ "$IS_MOUNTED" = "true" ]; then
    TEST_SCRIPT="$MOUNT_POINT/.verification_test.sh"
    
    # Try to create a script
    if echo -e "#!/bin/bash\necho executed" > "$TEST_SCRIPT" 2>/dev/null; then
        TEST_SCRIPT_CREATED="true"
        chmod +x "$TEST_SCRIPT" 2>/dev/null
        
        # Try to execute - capture both stdout and stderr
        # We expect this to FAIL if noexec is working
        OUTPUT=$("$TEST_SCRIPT" 2>&1)
        EXIT_CODE=$?
        TEST_OUTPUT="$OUTPUT"
        
        # If exit code is 126 (Command invoked cannot execute) or error contains Permission denied
        if [[ "$OUTPUT" == *"Permission denied"* ]] || [ "$EXIT_CODE" -eq 126 ]; then
            NOEXEC_ACTIVE="true"
        fi
        
        # Cleanup
        rm -f "$TEST_SCRIPT" 2>/dev/null
    else
        # Could not create file - possibly read-only mount?
        # If we can't write, we can't test exec, but RO implicitly prevents exec of new files
        echo "Could not create test script (Read-Only?)"
    fi
fi

# 4. Check files accessibility
FILES_LIST=""
FILES_COUNT=0
if [ "$IS_MOUNTED" = "true" ]; then
    FILES_LIST=$(ls -1 "$MOUNT_POINT" 2>/dev/null | tr '\n' ',')
    FILES_COUNT=$(ls -1 "$MOUNT_POINT" 2>/dev/null | wc -l)
fi

# 5. Check report
REPORT_EXISTS="false"
REPORT_CONTENT=""
REPORT_SIZE=0
if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_SIZE=$(stat -c%s "$REPORT_PATH" 2>/dev/null || echo "0")
    # Read first 4KB of report for verification
    REPORT_CONTENT=$(cat "$REPORT_PATH" | head -c 4096)
fi

# 6. Timestamps and other metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CURRENT_TIME=$(date +%s)
INITIAL_MOUNT_COUNT=$(cat /tmp/initial_mount_count.txt 2>/dev/null || echo "0")
CURRENT_MOUNT_COUNT=$(mount | grep "veracrypt" | wc -l)

# Take screenshot
take_screenshot /tmp/task_final.png

# Create JSON Result using Python to handle escaping safely
python3 -c "
import json
import os

try:
    data = {
        'is_mounted': '$IS_MOUNTED' == 'true',
        'mount_point': '$MOUNT_POINT',
        'mount_options': '$MOUNT_OPTIONS',
        'noexec_active': '$NOEXEC_ACTIVE' == 'true',
        'test_script_created': '$TEST_SCRIPT_CREATED' == 'true',
        'test_execution_output': '$TEST_OUTPUT',
        'files_count': int('$FILES_COUNT'),
        'files_list': '$FILES_LIST',
        'report_exists': '$REPORT_EXISTS' == 'true',
        'report_size': int('$REPORT_SIZE'),
        'report_content': '''$REPORT_CONTENT''',
        'task_start': int('$TASK_START'),
        'task_end': int('$CURRENT_TIME'),
        'initial_mount_count': int('$INITIAL_MOUNT_COUNT'),
        'current_mount_count': int('$CURRENT_MOUNT_COUNT')
    }
    
    with open('/tmp/task_result.json', 'w') as f:
        json.dump(data, f)
except Exception as e:
    print(f'Error generating JSON: {e}')
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="