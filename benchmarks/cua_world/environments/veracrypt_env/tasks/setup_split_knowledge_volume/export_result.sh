#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Split Knowledge Volume Result ==="

VOLUME_PATH="/home/ga/Volumes/master_keys.hc"
SEED_SOURCE="/home/ga/Sensitive/master_seed.txt"
PASSWORD="SharedAccess2025"
KF1="/home/ga/Dept_IT/it_token.bin"
KF2="/home/ga/Dept_Security/sec_cert.pem"
KF3="/home/ga/Dept_Compliance/audit_policy.pdf"

# Record Task End
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Volume Existence
VOLUME_EXISTS="false"
VOLUME_SIZE=0
if [ -f "$VOLUME_PATH" ]; then
    VOLUME_EXISTS="true"
    VOLUME_SIZE=$(stat -c%s "$VOLUME_PATH" 2>/dev/null || echo "0")
fi

# 2. Check Source File Removal (Did they move it?)
SEED_REMOVED_FROM_SOURCE="false"
if [ ! -f "$SEED_SOURCE" ]; then
    SEED_REMOVED_FROM_SOURCE="true"
fi

# 3. VERIFICATION TESTS
# We need to perform these tests programmatically because the Python verifier
# cannot execute commands inside the container.

# Force dismount everything first to ensure clean test state
veracrypt --text --dismount --non-interactive 2>/dev/null || true
sleep 1

# TEST A: Positive Access (Pass + All 3 Keyfiles)
TEST_POSITIVE_MOUNT="false"
TEST_SEED_FOUND_INSIDE="false"
MOUNT_DIR="/tmp/vc_verify_pos"
mkdir -p "$MOUNT_DIR"

echo "Running Positive Access Test..."
if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_DIR" \
    --password="$PASSWORD" \
    --keyfiles="$KF1,$KF2,$KF3" \
    --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
    
    TEST_POSITIVE_MOUNT="true"
    
    # Check for seed file inside
    if [ -f "$MOUNT_DIR/master_seed.txt" ]; then
        TEST_SEED_FOUND_INSIDE="true"
    fi
    
    # Dismount
    veracrypt --text --dismount "$MOUNT_DIR" --non-interactive 2>/dev/null || true
else
    echo "Positive mount failed."
fi
rmdir "$MOUNT_DIR" 2>/dev/null || true

# TEST B: Negative Access (Pass + Only 2 Keyfiles) - Anti-gaming check
# If this succeeds, the agent didn't add all keyfiles (e.g., they only added 2, or none)
TEST_NEGATIVE_MISSING_KEY="false"
MOUNT_DIR="/tmp/vc_verify_neg"
mkdir -p "$MOUNT_DIR"

echo "Running Negative Access Test (Missing Keyfile)..."
if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_DIR" \
    --password="$PASSWORD" \
    --keyfiles="$KF1,$KF2" \
    --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
    
    # IT MOUNTED - THIS IS BAD (FAILURE CONDITION)
    TEST_NEGATIVE_MISSING_KEY="true" # "true" here means the test FAILED to block access
    veracrypt --text --dismount "$MOUNT_DIR" --non-interactive 2>/dev/null || true
else
    # IT FAILED TO MOUNT - THIS IS GOOD
    TEST_NEGATIVE_MISSING_KEY="false"
fi
rmdir "$MOUNT_DIR" 2>/dev/null || true

# TEST C: Negative Access (Password Only)
TEST_NEGATIVE_PASS_ONLY="false"
MOUNT_DIR="/tmp/vc_verify_pass"
mkdir -p "$MOUNT_DIR"

echo "Running Negative Access Test (Password Only)..."
if veracrypt --text --mount "$VOLUME_PATH" "$MOUNT_DIR" \
    --password="$PASSWORD" \
    --keyfiles="" \
    --pim=0 --protect-hidden=no --non-interactive > /dev/null 2>&1; then
    
    TEST_NEGATIVE_PASS_ONLY="true" # Bad
    veracrypt --text --dismount "$MOUNT_DIR" --non-interactive 2>/dev/null || true
else
    TEST_NEGATIVE_PASS_ONLY="false" # Good
fi
rmdir "$MOUNT_DIR" 2>/dev/null || true


# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOLUME_EXISTS,
    "volume_size": $VOLUME_SIZE,
    "seed_removed_from_source": $SEED_REMOVED_FROM_SOURCE,
    "positive_mount_success": $TEST_POSITIVE_MOUNT,
    "seed_found_inside": $TEST_SEED_FOUND_INSIDE,
    "negative_missing_key_mounted": $TEST_NEGATIVE_MISSING_KEY,
    "negative_pass_only_mounted": $TEST_NEGATIVE_PASS_ONLY,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="