#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Results for Reset Credentials ==="

VOL_PATH="/home/ga/Volumes/DepartedUser.hc"
RESULT_FILE="/tmp/task_result.json"
MOUNT_POINT="/tmp/verify_mount"

# Initialize state variables
VOL_EXISTS="false"
NEW_CREDS_WORK="false"
OLD_CREDS_FAIL="false"
DATA_INTACT="false"
FILES_FOUND=""

# Check 1: Volume file existence
if [ -f "$VOL_PATH" ]; then
    VOL_EXISTS="true"
fi

# Check 2: Mount with NEW credentials
# The goal: Password="Archive2025", PIM=0 (default), Keyfiles="" (none)
mkdir -p "$MOUNT_POINT"
echo "Attempting mount with NEW credentials..."

if veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
    --password="Archive2025" \
    --pim=0 \
    --keyfiles="" \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    
    NEW_CREDS_WORK="true"
    
    # Check 3: Data integrity
    if [ -f "$MOUNT_POINT/Project_Specs.pdf" ]; then
        DATA_INTACT="true"
        FILES_FOUND=$(ls -m "$MOUNT_POINT")
    fi
    
    # Dismount
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
else
    echo "Failed to mount with new credentials."
fi

# Check 4: Mount with OLD credentials (Negative Test)
# This should FAIL if the password was actually changed.
echo "Attempting mount with OLD credentials..."

if veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
    --password='Complex#88' \
    --pim=1001 \
    --keyfiles='/home/ga/Keyfiles/security_token.key' \
    --protect-hidden=no \
    --non-interactive >/dev/null 2>&1; then
    
    OLD_CREDS_FAIL="false" # Bad: Old credentials still work
    veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
else
    OLD_CREDS_FAIL="true" # Good: Old credentials rejected
fi

# Cleanup
rmdir "$MOUNT_POINT" 2>/dev/null || true

# Capture final state
take_screenshot /tmp/task_final.png

# Create result JSON
# Using python to write JSON avoids quoting hell in bash
python3 -c "
import json
result = {
    'volume_exists': $VOL_EXISTS,
    'new_creds_work': $NEW_CREDS_WORK,
    'old_creds_fail': $OLD_CREDS_FAIL,
    'data_intact': $DATA_INTACT,
    'files_found': \"$FILES_FOUND\",
    'timestamp': $(date +%s)
}
with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f)
"

# Handle permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Result saved to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export Complete ==="