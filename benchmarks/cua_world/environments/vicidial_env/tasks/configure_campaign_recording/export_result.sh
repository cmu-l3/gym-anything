#!/bin/bash
set -e

echo "=== Exporting Configure Campaign Recording result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# ==============================================================================
# DATA EXTRACTION
# ==============================================================================

CAMPAIGN_ID="FINSVC01"

# Query the 3 specific fields we care about
# We use separate queries to handle potential empty strings/NULLs cleanly in shell

# 1. Recording Mode
REC_MODE=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sNe "SELECT campaign_rec FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")

# 2. Filename
# Use 'echo' to handle potentially empty result if mysql returns nothing for empty string
REC_FILENAME=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sNe "SELECT campaign_rec_filename FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")

# 3. Delay
REC_DELAY=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sNe "SELECT allcalls_delay FROM vicidial_campaigns WHERE campaign_id='$CAMPAIGN_ID'")

# Check if admin log shows recent activity (Anti-gaming)
# We look for a modification to campaign FINSVC01 after our start time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
# Vicidial stores logs in vicidial_admin_log. event_date is DATETIME.
# We count logs for this campaign since task start.
# Note: SQL 'NOW()' inside container might differ slightly from host date +%s, but strictly > check usually works if clock is synced. 
# We'll just check if *any* log exists for this campaign that is recent.
MODIFICATION_COUNT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -sNe "SELECT COUNT(*) FROM vicidial_admin_log WHERE record_id='$CAMPAIGN_ID' AND event_date >= FROM_UNIXTIME($TASK_START)")

# ==============================================================================
# JSON GENERATION
# ==============================================================================

# Create JSON using python to avoid shell quoting issues with special chars in filename
python3 -c "
import json
import os

result = {
    'campaign_id': '$CAMPAIGN_ID',
    'actual_rec_mode': '$REC_MODE',
    'actual_filename': '''$REC_FILENAME''',
    'actual_delay': '$REC_DELAY',
    'modification_log_count': int('$MODIFICATION_COUNT'),
    'task_timestamp': $TASK_START,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions so the host can read it (if mapped, though copy_from_env handles this)
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Exported JSON:"
cat /tmp/task_result.json
echo "=== Export complete ==="