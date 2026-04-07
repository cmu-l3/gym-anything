#!/bin/bash
echo "=== Setting up create_project_with_tasks task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial counts
INITIAL_PROJ=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='Project' AND deleted=0" | tr -d '[:space:]')
INITIAL_PT=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='ProjectTask' AND deleted=0" | tr -d '[:space:]')
INITIAL_PM=$(vtiger_db_query "SELECT COUNT(*) FROM vtiger_crmentity WHERE setype='ProjectMilestone' AND deleted=0" | tr -d '[:space:]')

echo "$INITIAL_PROJ" > /tmp/initial_proj_count.txt
echo "$INITIAL_PT" > /tmp/initial_pt_count.txt
echo "$INITIAL_PM" > /tmp/initial_pm_count.txt

# Remove existing target project to ensure clean state
EXISTING_PROJ=$(vtiger_db_query "SELECT projectid FROM vtiger_project WHERE projectname='Riverside Office Park - Landscape Renovation' LIMIT 1" | tr -d '[:space:]')
if [ -n "$EXISTING_PROJ" ]; then
    echo "Removing existing project and related records..."
    # Hide linked tasks
    vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE crmid IN (SELECT projecttaskid FROM vtiger_projecttask WHERE projectid=$EXISTING_PROJ)"
    # Hide linked milestones
    vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE crmid IN (SELECT projectmilestoneid FROM vtiger_projectmilestone WHERE projectid=$EXISTING_PROJ)"
    # Hide project
    vtiger_db_query "UPDATE vtiger_crmentity SET deleted=1 WHERE crmid=$EXISTING_PROJ"
fi

# Ensure logged in and navigate to Projects list
ensure_vtiger_logged_in "http://localhost:8000/index.php?module=Project&view=List"
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== setup complete ==="