#!/bin/bash
echo "=== Exporting Configure Advanced Polling Result ==="

source /workspace/scripts/task_utils.sh

JOB_NAME="legacy-inventory-sync"
OUTPUT_FILE="/tmp/task_result.json"

# Take final screenshot
take_screenshot /tmp/task_final.png

# Check if job exists
if ! job_exists "$JOB_NAME"; then
    echo "Job '$JOB_NAME' not found!"
    echo '{"job_exists": false}' > "$OUTPUT_FILE"
    exit 0
fi

# Get job configuration
CONFIG_XML=$(get_job_config "$JOB_NAME")

# Extract SCM Trigger Spec (Polling Schedule)
# Look for hudson.triggers.SCMTrigger -> spec
POLL_SPEC=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//hudson.triggers.SCMTrigger/spec" 2>/dev/null || echo "")

# Fallback grep if xmlstarlet fails or structure differs
if [ -z "$POLL_SPEC" ]; then
    # Grep context around SCMTrigger and look for spec
    POLL_SPEC=$(echo "$CONFIG_XML" | grep -A 5 "hudson.triggers.SCMTrigger" | grep "<spec>" | sed -e 's/.*<spec>//' -e 's/<\/spec>.*//' || echo "")
fi

# Extract Quiet Period
# Look for <quietPeriod> tag at top level of project
QUIET_PERIOD=$(echo "$CONFIG_XML" | xmlstarlet sel -t -v "//quietPeriod" 2>/dev/null || echo "")

if [ -z "$QUIET_PERIOD" ]; then
    QUIET_PERIOD=$(echo "$CONFIG_XML" | grep "<quietPeriod>" | sed -e 's/.*<quietPeriod>//' -e 's/<\/quietPeriod>.*//' || echo "null")
fi

# Check if config actually changed
CURRENT_HASH=$(echo "$CONFIG_XML" | md5sum)
INITIAL_HASH=$(cat /tmp/initial_config_hash.txt 2>/dev/null || echo "")
CONFIG_CHANGED="false"
if [ "$CURRENT_HASH" != "$INITIAL_HASH" ]; then
    CONFIG_CHANGED="true"
fi

# Create JSON result
# Using python to create JSON to avoid quoting issues with cron specs
python3 -c "
import json
import os

result = {
    'job_exists': True,
    'config_changed': '$CONFIG_CHANGED' == 'true',
    'poll_spec': '''$POLL_SPEC''',
    'quiet_period': '$QUIET_PERIOD',
    'timestamp': '$(date +%s)'
}

with open('$OUTPUT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# Set permissions
chmod 666 "$OUTPUT_FILE"

echo "Exported configuration:"
cat "$OUTPUT_FILE"
echo "=== Export Complete ==="