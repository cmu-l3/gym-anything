#!/bin/bash
echo "=== Exporting telemarketer_log_call_and_task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Lead
LEAD_ID=$(vtiger_db_query "SELECT leadid FROM vtiger_leaddetails WHERE firstname='David' AND lastname='Miller' AND company='Maersk Logistics' LIMIT 1" | tr -d '[:space:]')
LEAD_SOURCE=""
LEAD_STATUS=""
LEAD_INDUSTRY=""
LEAD_CREATED=0

if [ -n "$LEAD_ID" ]; then
    LEAD_INFO=$(vtiger_db_query "SELECT leadsource, leadstatus, industry FROM vtiger_leaddetails WHERE leadid=$LEAD_ID LIMIT 1")
    LEAD_SOURCE=$(echo "$LEAD_INFO" | awk -F'\t' '{print $1}')
    LEAD_STATUS=$(echo "$LEAD_INFO" | awk -F'\t' '{print $2}')
    LEAD_INDUSTRY=$(echo "$LEAD_INFO" | awk -F'\t' '{print $3}')
    LEAD_CREATED=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(createdtime) FROM vtiger_crmentity WHERE crmid=$LEAD_ID" | tr -d '[:space:]')
fi

# 2. Check Event (Call)
EVENT_ID=$(vtiger_db_query "SELECT activityid FROM vtiger_activity WHERE subject='Initial Discovery Call' AND activitytype='Call' LIMIT 1" | tr -d '[:space:]')
EVENT_STATUS=""
EVENT_DATE=""
EVENT_LINKED_TO_LEAD="false"
EVENT_CREATED=0

if [ -n "$EVENT_ID" ]; then
    EVENT_INFO=$(vtiger_db_query "SELECT eventstatus, date_start FROM vtiger_activity WHERE activityid=$EVENT_ID LIMIT 1")
    EVENT_STATUS=$(echo "$EVENT_INFO" | awk -F'\t' '{print $1}')
    EVENT_DATE=$(echo "$EVENT_INFO" | awk -F'\t' '{print $2}')
    
    if [ -n "$LEAD_ID" ]; then
        LINK=$(vtiger_db_query "SELECT crmid FROM vtiger_seactivityrel WHERE activityid=$EVENT_ID AND crmid=$LEAD_ID LIMIT 1" | tr -d '[:space:]')
        if [ -n "$LINK" ]; then EVENT_LINKED_TO_LEAD="true"; fi
    fi
    EVENT_CREATED=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(createdtime) FROM vtiger_crmentity WHERE crmid=$EVENT_ID" | tr -d '[:space:]')
fi

# 3. Check Task (To Do)
TASK_ID=$(vtiger_db_query "SELECT activityid FROM vtiger_activity WHERE subject='Send Maersk Pricing Deck' AND activitytype='Task' LIMIT 1" | tr -d '[:space:]')
TASK_STATUS=""
TASK_PRIORITY=""
TASK_DUE_DATE=""
TASK_LINKED_TO_LEAD="false"
TASK_CREATED=0

if [ -n "$TASK_ID" ]; then
    TASK_INFO=$(vtiger_db_query "SELECT status, priority, due_date FROM vtiger_activity WHERE activityid=$TASK_ID LIMIT 1")
    TASK_STATUS=$(echo "$TASK_INFO" | awk -F'\t' '{print $1}')
    TASK_PRIORITY=$(echo "$TASK_INFO" | awk -F'\t' '{print $2}')
    TASK_DUE_DATE=$(echo "$TASK_INFO" | awk -F'\t' '{print $3}')
    
    if [ -n "$LEAD_ID" ]; then
        LINK=$(vtiger_db_query "SELECT crmid FROM vtiger_seactivityrel WHERE activityid=$TASK_ID AND crmid=$LEAD_ID LIMIT 1" | tr -d '[:space:]')
        if [ -n "$LINK" ]; then TASK_LINKED_TO_LEAD="true"; fi
    fi
    TASK_CREATED=$(vtiger_db_query "SELECT UNIX_TIMESTAMP(createdtime) FROM vtiger_crmentity WHERE crmid=$TASK_ID" | tr -d '[:space:]')
fi

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Build the JSON result safely
RESULT_JSON=$(cat << JSONEOF
{
  "task_start_time": ${TASK_START:-0},
  "lead": {
    "found": $(if [ -n "$LEAD_ID" ]; then echo "true"; else echo "false"; fi),
    "source": "$(json_escape "${LEAD_SOURCE:-}")",
    "status": "$(json_escape "${LEAD_STATUS:-}")",
    "industry": "$(json_escape "${LEAD_INDUSTRY:-}")",
    "created_time": ${LEAD_CREATED:-0}
  },
  "event": {
    "found": $(if [ -n "$EVENT_ID" ]; then echo "true"; else echo "false"; fi),
    "status": "$(json_escape "${EVENT_STATUS:-}")",
    "date_start": "$(json_escape "${EVENT_DATE:-}")",
    "linked_to_lead": ${EVENT_LINKED_TO_LEAD},
    "created_time": ${EVENT_CREATED:-0}
  },
  "task": {
    "found": $(if [ -n "$TASK_ID" ]; then echo "true"; else echo "false"; fi),
    "status": "$(json_escape "${TASK_STATUS:-}")",
    "priority": "$(json_escape "${TASK_PRIORITY:-}")",
    "due_date": "$(json_escape "${TASK_DUE_DATE:-}")",
    "linked_to_lead": ${TASK_LINKED_TO_LEAD},
    "created_time": ${TASK_CREATED:-0}
  }
}
JSONEOF
)

safe_write_result "/tmp/telemarketer_result.json" "$RESULT_JSON"
echo "=== Export complete ==="