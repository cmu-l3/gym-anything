#!/bin/bash
echo "=== Exporting fabrication_blueprint_export result ==="
source /workspace/scripts/task_utils.sh || exit 1

take_screenshot /tmp/fabrication_task_final.png 2>/dev/null || true

ORK_FILE="/home/ga/Documents/rockets/manufacturing_ready.ork"
PDF_FILE="/home/ga/Documents/exports/manufacturing_blueprints.pdf"
START_TS_FILE="/tmp/fabrication_task_gt.txt"

ork_exists="false"
pdf_exists="false"
ork_size=0
pdf_size=0
pdf_created_during_task="false"

task_start_ts=0
if [ -f "$START_TS_FILE" ]; then
    task_start_ts=$(grep "task_start_ts=" "$START_TS_FILE" | cut -d'=' -f2)
fi

if [ -f "$ORK_FILE" ]; then
    ork_exists="true"
    ork_size=$(stat -c %s "$ORK_FILE" 2>/dev/null)
fi

if [ -f "$PDF_FILE" ]; then
    pdf_exists="true"
    pdf_size=$(stat -c %s "$PDF_FILE" 2>/dev/null)
    pdf_mtime=$(stat -c %Y "$PDF_FILE" 2>/dev/null)
    
    if [ "$pdf_mtime" -gt "$task_start_ts" ]; then
        pdf_created_during_task="true"
    fi
fi

write_result_json "{
  \"ork_exists\": $ork_exists,
  \"ork_size\": $ork_size,
  \"pdf_exists\": $pdf_exists,
  \"pdf_size\": $pdf_size,
  \"pdf_created_during_task\": $pdf_created_during_task,
  \"task_start_ts\": $task_start_ts
}" /tmp/fabrication_result.json

echo "=== Export complete ==="