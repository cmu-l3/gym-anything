#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Create Keyfile Result ==="

KEYFILE_PATH="/home/ga/Keyfiles/my_keyfile.key"
KEYFILE_DIR="/home/ga/Keyfiles"

# Check if the keyfile exists at expected path
KEYFILE_EXISTS="false"
KEYFILE_SIZE=0

if [ -f "$KEYFILE_PATH" ]; then
    KEYFILE_EXISTS="true"
    KEYFILE_SIZE=$(stat -c%s "$KEYFILE_PATH" 2>/dev/null || echo "0")
    echo "Keyfile found: $KEYFILE_PATH ($KEYFILE_SIZE bytes)"
fi

# Check if any new keyfile was created in the Keyfiles directory
INITIAL_COUNT=$(cat /tmp/initial_keyfile_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(ls -1 "$KEYFILE_DIR" 2>/dev/null | wc -l)
NEW_KEYFILE_CREATED="false"
if [ "$CURRENT_COUNT" -gt "$INITIAL_COUNT" ]; then
    NEW_KEYFILE_CREATED="true"
fi

# Look for any .key files that may have been created elsewhere
OTHER_KEYFILES=""
for f in /home/ga/Keyfiles/*.key /home/ga/*.key /home/ga/Desktop/*.key /tmp/*.key; do
    if [ -f "$f" ] 2>/dev/null; then
        OTHER_KEYFILES="$OTHER_KEYFILES$(basename "$f"),"
    fi
done

# Check keyfile validity (VeraCrypt keyfiles should be at least 64 bytes)
KEYFILE_VALID="false"
if [ "$KEYFILE_EXISTS" = "true" ] && [ "$KEYFILE_SIZE" -ge 64 ]; then
    KEYFILE_VALID="true"
fi

# Take screenshot
take_screenshot /tmp/task_end.png

# Write result
RESULT_JSON=$(cat << EOF
{
    "keyfile_exists": $KEYFILE_EXISTS,
    "keyfile_path": "$KEYFILE_PATH",
    "keyfile_size": $KEYFILE_SIZE,
    "keyfile_valid": $KEYFILE_VALID,
    "new_keyfile_created": $NEW_KEYFILE_CREATED,
    "initial_keyfile_count": $INITIAL_COUNT,
    "current_keyfile_count": $CURRENT_COUNT,
    "other_keyfiles": "$(echo "$OTHER_KEYFILES" | sed 's/"/\\"/g')",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/veracrypt_keyfile_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/veracrypt_keyfile_result.json"
cat /tmp/veracrypt_keyfile_result.json

echo "=== Export Complete ==="
