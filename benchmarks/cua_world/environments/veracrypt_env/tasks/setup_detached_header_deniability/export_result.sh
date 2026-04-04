#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Detached Header Results ==="

# Configuration
VOL_PATH="/home/ga/SecureTransport/ghost_data.hc"
HEADER_PATH="/home/ga/SecureTransport/ghost_header.vc"
PASSWORD="ProtocolGhost2024!"
MOUNT_POINT="/tmp/vc_check_mount"
SAMPLE_FILE="SF312_Nondisclosure_Agreement.txt"

# Initialize results
VOL_EXISTS="false"
HEADER_EXISTS="false"
PRIMARY_WIPED="false"
BACKUP_WIPED="false"
EXTERNAL_MOUNT_OK="false"
DATA_INTACT="false"

# 1. Check file existence
if [ -f "$VOL_PATH" ]; then
    VOL_EXISTS="true"
    VOL_SIZE=$(stat -c%s "$VOL_PATH")
fi

if [ -f "$HEADER_PATH" ]; then
    HEADER_EXISTS="true"
fi

# Ensure mount point exists
mkdir -p "$MOUNT_POINT"

# 2. Test: Standard Mount (Should FAIL if primary header is wiped)
echo "Testing standard mount (expecting failure)..."
if [ "$VOL_EXISTS" = "true" ]; then
    if veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
        --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no \
        --non-interactive >/dev/null 2>&1; then
        echo "FAIL: Standard mount succeeded (Primary header NOT wiped)"
        PRIMARY_WIPED="false"
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
    else
        echo "PASS: Standard mount failed"
        PRIMARY_WIPED="true"
    fi
fi

# 3. Test: Backup Header Mount (Should FAIL if backup header is wiped)
echo "Testing backup header mount (expecting failure)..."
if [ "$VOL_EXISTS" = "true" ]; then
    if veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
        --use-backup-header \
        --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no \
        --non-interactive >/dev/null 2>&1; then
        echo "FAIL: Backup header mount succeeded (Backup header NOT wiped)"
        BACKUP_WIPED="false"
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
    else
        echo "PASS: Backup header mount failed"
        BACKUP_WIPED="true"
    fi
fi

# 4. Test: External Header Mount (Should SUCCEED)
echo "Testing external header mount (expecting success)..."
if [ "$VOL_EXISTS" = "true" ] && [ "$HEADER_EXISTS" = "true" ]; then
    if veracrypt --text --mount "$VOL_PATH" "$MOUNT_POINT" \
        --header "$HEADER_PATH" \
        --password="$PASSWORD" --pim=0 --keyfiles="" --protect-hidden=no \
        --non-interactive >/dev/null 2>&1; then
        echo "PASS: External header mount succeeded"
        EXTERNAL_MOUNT_OK="true"
        
        # 5. Check Data Integrity
        if [ -f "$MOUNT_POINT/$SAMPLE_FILE" ]; then
            echo "PASS: Data file found"
            DATA_INTACT="true"
        else
            echo "FAIL: Data file missing"
            ls -la "$MOUNT_POINT"
        fi
        
        # Cleanup
        veracrypt --text --dismount "$MOUNT_POINT" --non-interactive >/dev/null 2>&1
    else
        echo "FAIL: External header mount failed"
    fi
fi

rmdir "$MOUNT_POINT" 2>/dev/null

# Capture final screenshot
take_screenshot /tmp/task_end.png

# Create JSON Result
RESULT_JSON=$(cat << EOF
{
    "volume_exists": $VOL_EXISTS,
    "header_exists": $HEADER_EXISTS,
    "primary_header_wiped": $PRIMARY_WIPED,
    "backup_header_wiped": $BACKUP_WIPED,
    "external_mount_works": $EXTERNAL_MOUNT_OK,
    "data_intact": $DATA_INTACT,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/detached_header_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/detached_header_result.json"
cat /tmp/detached_header_result.json

echo "=== Export Complete ==="