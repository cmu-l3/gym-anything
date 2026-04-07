#!/bin/bash
echo "=== Setting up strategic_taskforce_time_configuration task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

log "Cleaning up prior run artifacts..."

# Clean up any existing project resources, tasks, and the project itself
sentrifugo_db_root_query "DELETE FROM main_projectresources WHERE project_id IN (SELECT id FROM main_projects WHERE projectname='AI Enterprise Integration');" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_projecttasks WHERE project_id IN (SELECT id FROM main_projects WHERE projectname='AI Enterprise Integration');" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_projects WHERE projectname='AI Enterprise Integration';" 2>/dev/null || true

# Clean up the client
sentrifugo_db_root_query "DELETE FROM main_clients WHERE clientname='Executive Strategy Board';" 2>/dev/null || true

log "Cleanup complete"

# ---- Drop initiative charter on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/taskforce_charter.txt << 'CHARTER'
ACME GLOBAL TECHNOLOGIES
Strategic Initiative Charter — Confidential
=========================================

INITIATIVE OVERVIEW
-------------------
We are launching a cross-functional taskforce to evaluate and pilot Enterprise AI integration.
To track capitalized hours correctly, the Sentrifugo Time module must be configured before
the kickoff meeting this afternoon.

Please set up the following in the Sentrifugo Time module:

1. CLIENT CREATION
------------------
We are using an internal client to group executive initiatives.
  - Client Name: Executive Strategy Board
  - Status: Active

2. PROJECT CREATION
-------------------
  - Project Name: AI Enterprise Integration
  - Client: [Select the client created above]
  - Status: Active

3. PROJECT TASKS
----------------
Create these three specific trackable tasks under the AI Enterprise Integration project:
  a. Vendor Assessment
  b. Security Risk Analysis
  c. Pilot Implementation

4. RESOURCE ALLOCATION
----------------------
Allocate the following three employees to the project so they can log timesheets:
  - Jessica Liu (EMP006)
  - Jennifer Martinez (EMP012)
  - Kevin Robinson (EMP015)

NOTE: All items must be set to Active.
=========================================
CHARTER

chown ga:ga /home/ga/Desktop/taskforce_charter.txt
log "Charter document created at ~/Desktop/taskforce_charter.txt"

# ---- Navigate to Dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Maximize the window for better agent visibility
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

take_screenshot /tmp/task_start_screenshot.png

log "Task ready: taskforce charter on Desktop, Sentrifugo Time module clean."
echo "=== Setup complete ==="