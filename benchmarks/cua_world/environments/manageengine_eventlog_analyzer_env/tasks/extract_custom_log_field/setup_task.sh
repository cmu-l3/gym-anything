#!/bin/bash
# Setup for extract_custom_log_field task

echo "=== Setting up Custom Field Extraction Task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for ELA to be ready
wait_for_eventlog_analyzer

# 2. Record Start Time & Initial State
date +%s > /tmp/task_start_time.txt

# Check if field already exists (unlikely in fresh env, but good for idempotency/debugging)
# We search broadly in the conf directory where custom patterns are often stored
INITIAL_CONF_MATCH=$(grep -r "FinTransactionID" /opt/ManageEngine/EventLog/conf/ 2>/dev/null | wc -l)
echo "$INITIAL_CONF_MATCH" > /tmp/initial_conf_match_count.txt

# 3. Inject Real Log Data
# We use 'logger' to send syslog messages that ELA will index.
# We mimic a banking application 'FinCore'.
echo "Injecting FinCore application logs..."

# Generate some background noise
logger -t SystemMon "Checking disk space on /dev/sda1: 45% used"
logger -t SystemMon "Memory usage normal"

# Generate the target logs with Transaction IDs
for i in {1..15}; do
    # Generate random 6-digit ID
    TXN_ID="TXN-$((100000 + RANDOM % 900000))"
    STATUS=("Pending" "Completed" "Failed" "Verifying")
    RAND_STATUS=${STATUS[$RANDOM % ${#STATUS[@]}]}
    
    # Log message format: [FinCore] Payment processing started for Ref: TXN-XXXXXX - Status: YYYYY
    logger -t FinCore "Payment processing event for Ref: $TXN_ID - Status: $RAND_STATUS - User: merchant_api"
    
    sleep 0.5
done

echo "Logs injected. Waiting for indexing (10s)..."
sleep 10

# 4. Open Firefox to the Search Tab
# This puts the agent in the right place to start looking for logs
ensure_firefox_on_ela "/event/index.do#/search/index"

# 5. Capture Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="
echo "Target Logs: FinCore"
echo "Target Pattern: TXN-######"