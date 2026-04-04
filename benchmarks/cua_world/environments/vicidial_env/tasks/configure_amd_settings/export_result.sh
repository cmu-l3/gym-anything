#!/bin/bash
set -e
echo "=== Exporting AMD Configuration Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Query the Vicidial database for the final state of the campaign
# We use docker exec to run the query inside the container
echo "Querying campaign configuration..."
DB_RESULT=$(docker exec vicidial mysql -ucron -p1234 -D asterisk -N -B -e "
SELECT 
    campaign_vdad_exten, 
    amd_send_to_vmx, 
    amd_initial_silence, 
    amd_maximum_word_length, 
    amd_maximum_greeting 
FROM vicidial_campaigns 
WHERE campaign_id = 'AMD_OPTIM';
" 2>/dev/null || echo "")

# Parse the result (Tab separated)
# Expected format: 8369    8320    3500    2000    4000
ROUTING_EXT=$(echo "$DB_RESULT" | cut -f1)
VM_EXT=$(echo "$DB_RESULT" | cut -f2)
INIT_SILENCE=$(echo "$DB_RESULT" | cut -f3)
WORD_LEN=$(echo "$DB_RESULT" | cut -f4)
MAX_GREET=$(echo "$DB_RESULT" | cut -f5)

# Check if application was running
APP_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "campaign_found": $([ -n "$DB_RESULT" ] && echo "true" || echo "false"),
    "routing_ext": "$ROUTING_EXT",
    "vm_ext": "$VM_EXT",
    "initial_silence": "$INIT_SILENCE",
    "word_length": "$WORD_LEN",
    "max_greeting": "$MAX_GREET",
    "app_was_running": $APP_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location with permission handling
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="