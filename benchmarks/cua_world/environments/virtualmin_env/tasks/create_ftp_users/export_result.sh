#!/bin/bash
echo "=== Exporting create_ftp_users results ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Gather User Information via Virtualmin CLI
# We output raw text that Python can parse, or construct JSON here.
# JSON construction in bash is fragile, so we'll dump raw data and let Python parse it.

# Dump full user list details
virtualmin list-users --domain acmecorp.test --multiline > /tmp/virtualmin_users.txt 2>/dev/null || true

# 2. Gather System Level Information (Passwd)
# This is more reliable for Shell and Home Directory than Virtualmin CLI sometimes
grep -E "^alice_dev:|^dave_uploads:" /etc/passwd > /tmp/passwd_entries.txt 2>/dev/null || true

# 3. Check Directory Existence
UPLOADS_DIR_EXISTS="false"
if [ -d "/home/acmecorp/public_html/uploads" ]; then
    UPLOADS_DIR_EXISTS="true"
fi

# 4. Anti-Gaming: Check modification time of /etc/passwd to see if users were added recently
PASSWD_MTIME=$(stat -c %Y /etc/passwd 2>/dev/null || echo "0")
MODIFIED_DURING_TASK="false"
if [ "$PASSWD_MTIME" -ge "$TASK_START" ]; then
    MODIFIED_DURING_TASK="true"
fi

# 5. Get current user count
FINAL_USER_COUNT=$(virtualmin list-users --domain acmecorp.test --user-only 2>/dev/null | wc -l)
INITIAL_USER_COUNT=$(cat /tmp/initial_user_count.txt 2>/dev/null || echo "0")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_user_count": $INITIAL_USER_COUNT,
    "final_user_count": $FINAL_USER_COUNT,
    "passwd_modified_during_task": $MODIFIED_DURING_TASK,
    "uploads_dir_exists": $UPLOADS_DIR_EXISTS,
    "passwd_entries": "$(cat /tmp/passwd_entries.txt | sed 's/"/\\"/g' | tr '\n' ';')",
    "virtualmin_users_dump_path": "/tmp/virtualmin_users.txt",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"