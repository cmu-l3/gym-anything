#!/bin/bash
echo "=== Exporting create_project_with_tasks results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_PROJ=$(cat /tmp/initial_proj_count.txt 2>/dev/null || echo "0")
INITIAL_PT=$(cat /tmp/initial_pt_count.txt 2>/dev/null || echo "0")
INITIAL_PM=$(cat /tmp/initial_pm_count.txt 2>/dev/null || echo "0")

# Query project data
PROJ_DATA=$(vtiger_db_query "SELECT p.projectid, p.projectname, p.startdate, p.targetenddate, p.projectstatus, p.projectpriority, c.description, UNIX_TIMESTAMP(c.createdtime) FROM vtiger_project p INNER JOIN vtiger_crmentity c ON p.projectid = c.crmid WHERE p.projectname = 'Riverside Office Park - Landscape Renovation' AND c.deleted = 0 LIMIT 1")

if [ -n "$PROJ_DATA" ]; then
    P_ID=$(echo "$PROJ_DATA" | awk -F'\t' '{print $1}')
    P_NAME=$(echo "$PROJ_DATA" | awk -F'\t' '{print $2}')
    P_START=$(echo "$PROJ_DATA" | awk -F'\t' '{print $3}')
    P_END=$(echo "$PROJ_DATA" | awk -F'\t' '{print $4}')
    P_STATUS=$(echo "$PROJ_DATA" | awk -F'\t' '{print $5}')
    P_PRIORITY=$(echo "$PROJ_DATA" | awk -F'\t' '{print $6}')
    P_DESC=$(echo "$PROJ_DATA" | awk -F'\t' '{print $7}')
    P_CREATED=$(echo "$PROJ_DATA" | awk -F'\t' '{print $8}')

    # Retrieve tasks linked to project
    TASKS_DATA=$(vtiger_db_query "SELECT t.projecttaskname, t.startdate, t.enddate, t.projecttaskpriority, t.projecttaskprogress FROM vtiger_projecttask t INNER JOIN vtiger_crmentity c ON t.projecttaskid = c.crmid WHERE t.projectid = $P_ID AND c.deleted = 0")
    
    # Retrieve milestones linked to project
    MILESTONES_DATA=$(vtiger_db_query "SELECT m.projectmilestonename, m.projectmilestonedate FROM vtiger_projectmilestone m INNER JOIN vtiger_crmentity c ON m.projectmilestoneid = c.crmid WHERE m.projectid = $P_ID AND c.deleted = 0")
else
    P_ID=""
    P_NAME=""
    P_START=""
    P_END=""
    P_STATUS=""
    P_PRIORITY=""
    P_DESC=""
    P_CREATED="0"
    TASKS_DATA=""
    MILESTONES_DATA=""
fi

export P_ID P_NAME P_START P_END P_STATUS P_PRIORITY P_DESC P_CREATED TASKS_DATA MILESTONES_DATA TASK_START TASK_END INITIAL_PROJ INITIAL_PT INITIAL_PM

PYTHON_SCRIPT=$(cat << 'PYEOF'
import os
import json

project_found = bool(os.environ.get("P_ID"))
project = {}
if project_found:
    project = {
        "projectid": os.environ.get("P_ID", ""),
        "projectname": os.environ.get("P_NAME", ""),
        "startdate": os.environ.get("P_START", ""),
        "targetenddate": os.environ.get("P_END", ""),
        "projectstatus": os.environ.get("P_STATUS", ""),
        "projectpriority": os.environ.get("P_PRIORITY", ""),
        "description": os.environ.get("P_DESC", ""),
        "createdtime": int(os.environ.get("P_CREATED", "0") or "0")
    }

tasks_lines = os.environ.get("TASKS_DATA", "").strip().split("\n")
tasks = []
if os.environ.get("TASKS_DATA", "").strip():
    for line in tasks_lines:
        parts = line.split("\t")
        if len(parts) >= 5:
            tasks.append({
                "projecttaskname": parts[0],
                "startdate": parts[1],
                "enddate": parts[2],
                "projecttaskpriority": parts[3],
                "projecttaskprogress": parts[4]
            })

milestones_lines = os.environ.get("MILESTONES_DATA", "").strip().split("\n")
milestones = []
if os.environ.get("MILESTONES_DATA", "").strip():
    for line in milestones_lines:
        parts = line.split("\t")
        if len(parts) >= 2:
            milestones.append({
                "projectmilestonename": parts[0],
                "projectmilestonedate": parts[1]
            })

result = {
    "project_found": project_found,
    "project": project,
    "tasks": tasks,
    "milestones": milestones,
    "task_start": int(os.environ.get("TASK_START", "0") or "0"),
    "task_end": int(os.environ.get("TASK_END", "0") or "0"),
    "initial_proj_count": int(os.environ.get("INITIAL_PROJ", "0") or "0"),
    "initial_pt_count": int(os.environ.get("INITIAL_PT", "0") or "0"),
    "initial_pm_count": int(os.environ.get("INITIAL_PM", "0") or "0")
}

print(json.dumps(result))
PYEOF
)

FINAL_JSON=$(python3 -c "$PYTHON_SCRIPT")
safe_write_result "/tmp/task_result.json" "$FINAL_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== export complete ==="