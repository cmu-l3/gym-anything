#!/bin/bash
echo "=== Exporting process_lost_deal_followup results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

take_screenshot /tmp/task_final.png

# We use MariaDB JSON_OBJECT to reliably export strings without delimiter escaping bugs.
# 1. Query the Potential state
vtiger_db_query "SELECT JSON_OBJECT('found', true, 'id', p.potentialid, 'stage', p.sales_stage, 'desc', IFNULL(c.description, ''), 'modifiedtime', UNIX_TIMESTAMP(c.modifiedtime)) FROM vtiger_potential p INNER JOIN vtiger_crmentity c ON p.potentialid = c.crmid WHERE p.potentialname='Apex Corp - Q3 Hardware Restock' LIMIT 1" > /tmp/pot_data.json

if [ ! -s /tmp/pot_data.json ]; then
    echo '{"found": false}' > /tmp/pot_data.json
fi

# 2. Query the linked Document
vtiger_db_query "SELECT JSON_OBJECT('found', true, 'id', n.notesid, 'title', n.title, 'filename', IFNULL(n.filename, '')) FROM vtiger_notes n INNER JOIN vtiger_senotesrel sr ON sr.notesid = n.notesid INNER JOIN vtiger_potential p ON p.potentialid = sr.crmid WHERE p.potentialname='Apex Corp - Q3 Hardware Restock' AND n.title LIKE '%Competitor%' LIMIT 1" > /tmp/doc_data.json

if [ ! -s /tmp/doc_data.json ]; then
    echo '{"found": false}' > /tmp/doc_data.json
fi

# 3. Query the linked Follow-up Task
vtiger_db_query "SELECT JSON_OBJECT('found', true, 'id', a.activityid, 'subject', a.subject, 'date', a.due_date, 'status', a.status) FROM vtiger_activity a INNER JOIN vtiger_seactivityrel sa ON sa.activityid = a.activityid INNER JOIN vtiger_potential p ON p.potentialid = sa.crmid WHERE p.potentialname='Apex Corp - Q3 Hardware Restock' AND a.activitytype='Task' LIMIT 1" > /tmp/task_data.json

if [ ! -s /tmp/task_data.json ]; then
    echo '{"found": false}' > /tmp/task_data.json
fi

# Merge results into a final comprehensive JSON using jq
jq -n \
  --slurpfile pot /tmp/pot_data.json \
  --slurpfile doc /tmp/doc_data.json \
  --slurpfile tsk /tmp/task_data.json \
  --arg start "$TASK_START" \
  --arg end "$TASK_END" \
  '{
    "task_start": ($start | tonumber),
    "task_end": ($end | tonumber),
    "potential": $pot[0],
    "document": $doc[0],
    "task": $tsk[0]
  }' > /tmp/process_lost_deal_result.json

chmod 666 /tmp/process_lost_deal_result.json 2>/dev/null || true

echo "Data exported to /tmp/process_lost_deal_result.json"
cat /tmp/process_lost_deal_result.json

echo "=== Export complete ==="