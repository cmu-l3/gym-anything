#!/bin/bash
echo "=== Exporting scheduled backup task results ==="

source /workspace/scripts/task_utils.sh

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
BACKUP_CONFIG_DIR="/etc/webmin/virtual-server/backups"

# ---------------------------------------------------------------
# 1. Capture Final State Screenshot
# ---------------------------------------------------------------
take_screenshot /tmp/task_final.png

# ---------------------------------------------------------------
# 2. Collect Backup Configurations
# ---------------------------------------------------------------
# Virtualmin stores scheduled backups as files named with numbers (e.g., /etc/webmin/virtual-server/backups/1)
# We collect content of all such files created/modified after task start.

CONFIG_DATA="[]"
if [ -d "$BACKUP_CONFIG_DIR" ]; then
    # Find files that are purely numeric (Virtualmin ID format)
    CONFIG_FILES=$(find "$BACKUP_CONFIG_DIR" -maxdepth 1 -type f -regex '.*/[0-9]+')
    
    # Initialize JSON array build
    CONFIG_LIST=()
    
    for f in $CONFIG_FILES; do
        # Check timestamp to ensure it wasn't pre-existing (though we cleared them in setup)
        MTIME=$(stat -c %Y "$f")
        if [ "$MTIME" -ge "$TASK_START" ]; then
            # Read file content safely
            CONTENT=$(cat "$f" | base64 -w 0)
            CONFIG_LIST+=("{\"id\": \"$(basename "$f")\", \"mtime\": $MTIME, \"content_base64\": \"$CONTENT\"}")
        fi
    done
    
    # Join into JSON array
    if [ ${#CONFIG_LIST[@]} -gt 0 ]; then
        IFS=","
        CONFIG_DATA="[${CONFIG_LIST[*]}]"
        unset IFS
    fi
fi

# ---------------------------------------------------------------
# 3. Collect Domain IDs (for mapping names to IDs in verifier)
# ---------------------------------------------------------------
# Virtualmin configs use domain IDs, not names. We need the mapping.
DOMAINS_JSON="{}"
ACME_ID=$(get_domain_id "acmecorp.test")
NONPROFIT_ID=$(get_domain_id "nonprofitaid.test")
GLOBAL_ID=$(get_domain_id "globalshop.test")

# Construct JSON object manually
DOMAINS_JSON="{\"acmecorp.test\": \"$ACME_ID\", \"nonprofitaid.test\": \"$NONPROFIT_ID\", \"globalshop.test\": \"$GLOBAL_ID\"}"

# ---------------------------------------------------------------
# 4. Check Crontab
# ---------------------------------------------------------------
CRON_CONTENT=$(crontab -l 2>/dev/null | base64 -w 0 || echo "")

# ---------------------------------------------------------------
# 5. Build Final JSON
# ---------------------------------------------------------------
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "backup_configs": $CONFIG_DATA,
    "domain_map": $DOMAINS_JSON,
    "crontab_base64": "$CRON_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"