#!/bin/bash
source /workspace/scripts/task_utils.sh

echo "=== Exporting Prepare Volume for Distribution Result ==="

# Paths and Credentials
MASTER_VOL="/home/ga/Volumes/data_volume.hc"
CLONE_VOL="/home/ga/Volumes/financial_transfer.hc"
OLD_PASS="MountMe2024"
NEW_PASS="Transfer#2024"
NEW_PIM="485"

# --- CHECK 1: File Existence & Basic Properties ---
MASTER_EXISTS="false"
CLONE_EXISTS="false"
CLONE_IS_COPY="false"

if [ -f "$MASTER_VOL" ]; then MASTER_EXISTS="true"; fi

if [ -f "$CLONE_VOL" ]; then 
    CLONE_EXISTS="true"
    # Verify it's not a symlink to master
    if [ ! -L "$CLONE_VOL" ] && [ "$(stat -c %i "$MASTER_VOL")" != "$(stat -c %i "$CLONE_VOL")" ]; then
        CLONE_IS_COPY="true"
    fi
fi

# --- CHECK 2: Master Volume Integrity (Should open with OLD password) ---
MASTER_INTACT="false"
mkdir -p /tmp/check_master
if veracrypt --text --mount "$MASTER_VOL" /tmp/check_master \
    --password="$OLD_PASS" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
    MASTER_INTACT="true"
    veracrypt --text --dismount /tmp/check_master --non-interactive >/dev/null 2>&1
fi

# --- CHECK 3: Clone Security (Should FAIL with OLD password) ---
CLONE_REKEYED_OLD="false" # True if it fails to mount with old pass
if [ "$CLONE_EXISTS" = "true" ]; then
    if ! veracrypt --text --mount "$CLONE_VOL" /tmp/check_master \
        --password="$OLD_PASS" --pim=0 --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        CLONE_REKEYED_OLD="true"
    else
        # It mounted with old password, so clean up
        veracrypt --text --dismount /tmp/check_master --non-interactive >/dev/null 2>&1
    fi
fi
rmdir /tmp/check_master 2>/dev/null || true

# --- CHECK 4: Clone Access (Should SUCCESS with NEW password + PIM) ---
CLONE_ACCESS_SUCCESS="false"
DATA_PRESERVED="false"
NOTICE_EXISTS="false"
NOTICE_CONTENT_MATCH="false"

mkdir -p /tmp/check_clone
# Note: PIM must be passed. If PIM was not set, this mount will fail, which is correct (task requires PIM)
if [ "$CLONE_EXISTS" = "true" ]; then
    if veracrypt --text --mount "$CLONE_VOL" /tmp/check_clone \
        --password="$NEW_PASS" --pim="$NEW_PIM" --keyfiles="" --protect-hidden=no --non-interactive >/dev/null 2>&1; then
        
        CLONE_ACCESS_SUCCESS="true"
        
        # --- CHECK 5: Content Verification ---
        # 1. Check for original data
        if [ -f "/tmp/check_clone/FY2024_Revenue_Budget.csv" ] && [ -f "/tmp/check_clone/master_id.txt" ]; then
            DATA_PRESERVED="true"
        fi
        
        # 2. Check for new notice file
        if [ -f "/tmp/check_clone/transmittal_notice.txt" ]; then
            NOTICE_EXISTS="true"
            # Check content
            if grep -q "Authorized for transfer to External Auditor" "/tmp/check_clone/transmittal_notice.txt"; then
                NOTICE_CONTENT_MATCH="true"
            fi
        fi
        
        # Dismount
        veracrypt --text --dismount /tmp/check_clone --non-interactive >/dev/null 2>&1
    fi
fi
rmdir /tmp/check_clone 2>/dev/null || true

# Anti-gaming: Check if clone was created after task start
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CLONE_CTIME=$(stat -c %Y "$CLONE_VOL" 2>/dev/null || echo "0")
CREATED_DURING_TASK="false"
if [ "$CLONE_CTIME" -gt "$TASK_START" ]; then
    CREATED_DURING_TASK="true"
fi

# Take Final Screenshot
take_screenshot /tmp/task_final.png

# Generate Result JSON
RESULT_JSON=$(cat << EOF
{
    "master_exists": $MASTER_EXISTS,
    "clone_exists": $CLONE_EXISTS,
    "clone_is_distinct_file": $CLONE_IS_COPY,
    "created_during_task": $CREATED_DURING_TASK,
    "master_integrity_ok": $MASTER_INTACT,
    "clone_rejects_old_creds": $CLONE_REKEYED_OLD,
    "clone_accepts_new_creds": $CLONE_ACCESS_SUCCESS,
    "data_preserved": $DATA_PRESERVED,
    "notice_file_exists": $NOTICE_EXISTS,
    "notice_content_correct": $NOTICE_CONTENT_MATCH,
    "timestamp": "$(date -Iseconds)"
}
EOF
)

write_result_json "/tmp/task_result.json" "$RESULT_JSON"
cat /tmp/task_result.json # Output to logs
echo "=== Export Complete ==="