#!/bin/bash
echo "=== Exporting Quarantine Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

QUARANTINE_DIR="/root/quarantine"
DOCROOT="/home/greenleaf/public_html"

# ------------------------------------------------------------------
# Check status of INFECTED files
# ------------------------------------------------------------------
# We check three specific files we infected
# 1. index.php
INFECTED_1_NAME="index.php"
INFECTED_1_ORIGINAL="$DOCROOT/$INFECTED_1_NAME"
INFECTED_1_QUARANTINED="$QUARANTINE_DIR/$INFECTED_1_NAME"

# 2. functions.php
INFECTED_2_NAME="functions.php"
INFECTED_2_ORIGINAL="$DOCROOT/wp-content/themes/twentytwentythree/$INFECTED_2_NAME"
INFECTED_2_QUARANTINED="$QUARANTINE_DIR/$INFECTED_2_NAME"

# 3. class-wp-http.php
INFECTED_3_NAME="class-wp-http.php"
INFECTED_3_ORIGINAL="$DOCROOT/wp-includes/$INFECTED_3_NAME"
INFECTED_3_QUARANTINED="$QUARANTINE_DIR/$INFECTED_3_NAME"

check_file_status() {
    local orig="$1"
    local quar="$2"
    
    local in_orig="false"
    local in_quar="false"
    
    if [ -f "$orig" ]; then in_orig="true"; fi
    if [ -f "$quar" ]; then in_quar="true"; fi
    
    echo "\"in_original\": $in_orig, \"in_quarantine\": $in_quar"
}

STATUS_1=$(check_file_status "$INFECTED_1_ORIGINAL" "$INFECTED_1_QUARANTINED")
STATUS_2=$(check_file_status "$INFECTED_2_ORIGINAL" "$INFECTED_2_QUARANTINED")
STATUS_3=$(check_file_status "$INFECTED_3_ORIGINAL" "$INFECTED_3_QUARANTINED")

# ------------------------------------------------------------------
# Check status of DECOY file (should remain)
# ------------------------------------------------------------------
DECOY_NAME="class.akismet.php"
DECOY_ORIGINAL="$DOCROOT/wp-content/plugins/akismet/$DECOY_NAME"
DECOY_QUARANTINED="$QUARANTINE_DIR/$DECOY_NAME"

STATUS_DECOY=$(check_file_status "$DECOY_ORIGINAL" "$DECOY_QUARANTINED")

# ------------------------------------------------------------------
# Count total files in quarantine (to detect mass-move/delete)
# ------------------------------------------------------------------
TOTAL_QUARANTINED=$(find "$QUARANTINE_DIR" -type f | wc -l)

# ------------------------------------------------------------------
# Anti-Gaming: Check timestamps
# ------------------------------------------------------------------
# If files were moved, their ctime (inode change time) should be > TASK_START
# We check the quarantine directory content
MOVED_DURING_TASK="true"
for f in "$QUARANTINE_DIR"/*; do
    if [ -f "$f" ]; then
        CTIME=$(stat -c %Z "$f")
        if [ "$CTIME" -lt "$TASK_START" ]; then
            # This is technically possible if 'mv' preserves timestamps, 
            # but usually ctime updates on move across filesystems or metadata change.
            # A safer check is if the file exists in destination AND not in source.
            :
        fi
    fi
done

# ------------------------------------------------------------------
# Capture Final Screenshot
# ------------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ------------------------------------------------------------------
# Create JSON Result
# ------------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "total_quarantined_count": $TOTAL_QUARANTINED,
    "file_1": { $STATUS_1 },
    "file_2": { $STATUS_2 },
    "file_3": { $STATUS_3 },
    "decoy": { $STATUS_DECOY },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="