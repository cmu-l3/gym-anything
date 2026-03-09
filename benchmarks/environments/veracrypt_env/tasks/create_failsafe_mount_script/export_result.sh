#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Failsafe Script Result ==="

SCRIPT_PATH="/home/ga/Documents/safe_log_entry.sh"
VOLUME_PATH="/home/ga/Volumes/audit_volume.hc"
PASSWORD="SecureAudit2024!"

# Results dictionary
SCRIPT_EXISTS="false"
IS_EXECUTABLE="false"
HAS_TRAP="false"
POSITIVE_TEST_PASSED="false"
NEGATIVE_TEST_PASSED="false"
LOG_UPDATED="false"

# 1. Check if script exists and is executable
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    if [ -x "$SCRIPT_PATH" ]; then
        IS_EXECUTABLE="true"
    fi
    # Static check for trap
    if grep -q "trap" "$SCRIPT_PATH"; then
        HAS_TRAP="true"
    fi
fi

# ensure volume is unmounted before testing
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# 2. POSITIVE TEST: Run the script normally
if [ "$IS_EXECUTABLE" = "true" ]; then
    echo "Running Positive Test..."
    
    # Run as ga user, with timeout
    if timeout 30s su - ga -c "$SCRIPT_PATH '$PASSWORD'"; then
        echo "Script executed successfully (exit code 0)"
        
        # Check if volume is dismounted
        MOUNT_CHECK=$(veracrypt --text --list --non-interactive 2>&1)
        if ! echo "$MOUNT_CHECK" | grep -q "$VOLUME_PATH"; then
            echo "Volume correctly dismounted after run"
            
            # Check if log was updated
            mkdir -p /tmp/verify_mount
            veracrypt --text --mount "$VOLUME_PATH" /tmp/verify_mount \
                --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive
            
            CURRENT_LINES=$(wc -l < /tmp/verify_mount/audit_log.txt)
            INITIAL_LINES=$(cat /tmp/initial_log_lines.txt 2>/dev/null || echo "0")
            
            if [ "$CURRENT_LINES" -gt "$INITIAL_LINES" ]; then
                LOG_UPDATED="true"
                POSITIVE_TEST_PASSED="true"
            fi
            
            veracrypt --text --dismount /tmp/verify_mount --non-interactive 2>/dev/null || true
            rmdir /tmp/verify_mount 2>/dev/null || true
        else
            echo "FAIL: Volume left mounted after script execution"
            # Cleanup
            veracrypt --text --dismount --non-interactive 2>/dev/null || true
        fi
    else
        echo "FAIL: Script returned non-zero exit code or timed out"
    fi
fi

# 3. NEGATIVE TEST: Fault Injection
# We modify a copy of the script to fail immediately after mounting
# to verify if 'trap' catches the error/exit and dismounts.
if [ "$IS_EXECUTABLE" = "true" ]; then
    echo "Running Negative Test (Fault Injection)..."
    
    TEST_SCRIPT="/home/ga/Documents/test_fault_injection.sh"
    cp "$SCRIPT_PATH" "$TEST_SCRIPT"
    chmod +x "$TEST_SCRIPT"
    
    # Inject a 'false' command (failure) right after the mount command
    # We look for the line containing 'veracrypt' and '--mount'
    sed -i '/veracrypt.*--mount/a \
    echo "INJECTING FAULT..."\
    false # Simulate error\
    exit 1 # Ensure exit' "$TEST_SCRIPT"
    
    # Ensure volume is clean
    veracrypt --text --dismount --non-interactive 2>/dev/null || true
    
    # Run the faulty script
    # It SHOULD fail (return non-zero)
    su - ga -c "$TEST_SCRIPT '$PASSWORD'" 2>/dev/null || true
    
    # Now check if volume is mounted
    MOUNT_CHECK=$(veracrypt --text --list --non-interactive 2>&1)
    if echo "$MOUNT_CHECK" | grep -q "$VOLUME_PATH"; then
        echo "FAIL: Volume remains mounted after script crash"
        NEGATIVE_TEST_PASSED="false"
        # Cleanup
        veracrypt --text --dismount --non-interactive 2>/dev/null || true
    else
        echo "PASS: Volume was dismounted despite script crash"
        NEGATIVE_TEST_PASSED="true"
    fi
    
    rm -f "$TEST_SCRIPT"
fi

# Take final screenshot
take_screenshot /tmp/task_end.png

# Write result JSON
RESULT_JSON=$(cat << EOF
{
    "script_exists": $SCRIPT_EXISTS,
    "is_executable": $IS_EXECUTABLE,
    "has_trap_command": $HAS_TRAP,
    "positive_test_passed": $POSITIVE_TEST_PASSED,
    "log_updated": $LOG_UPDATED,
    "negative_test_passed": $NEGATIVE_TEST_PASSED,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="