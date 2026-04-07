#!/bin/bash
echo "=== Setting up client_portfolio_restructure task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60
date +%s > /tmp/task_start_timestamp

log "Injecting initial client and project data..."

# Clean up any artifacts from previous runs
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
DELETE FROM main_projects WHERE projectname IN ('General Plant Operations 2025', 'Biomass Grid Integration Phase 2', 'Facility Maintenance 2026');
DELETE FROM main_clients WHERE clientname='Pinnacle Renewable Energy';
" 2>/dev/null || true

# Inject the Client and the Legacy Project
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -e "
INSERT INTO main_clients (clientname, isactive) VALUES ('Pinnacle Renewable Energy', 1);
SET @cid = (SELECT id FROM main_clients WHERE clientname='Pinnacle Renewable Energy' LIMIT 1);
INSERT INTO main_projects (projectname, projectcode, client_id, isactive) VALUES ('General Plant Operations 2025', 'GPO-2025', @cid, 1);
" 2>/dev/null || true

log "Initial data injected successfully."

# Create the directive document on the Desktop
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q1_project_restructure.txt << 'DIRECTIVE'
======================================================
PROJECT PORTFOLIO RESTRUCTURE DIRECTIVE
Client: Pinnacle Renewable Energy
Effective Date: Immediate
Prepared By: Plant Operations Manager
======================================================

The generic "General Plant Operations 2025" project is 
being deprecated for the new fiscal year. Please deactivate
this project immediately to prevent further time logging.

Create the following two new projects under the 
"Pinnacle Renewable Energy" client account:

PROJECT 1: Biomass Grid Integration Phase 2
-------------------------------------------
Add the following Tasks to this project:
  - SCADA System Update
  - Grid Synchronization Tests
  - Safety Audit

Assign the following employees to this project:
  - David Kim (EMP005)
  - Jessica Liu (EMP006)

PROJECT 2: Facility Maintenance 2026
-------------------------------------------
Add the following Tasks to this project:
  - Turbine Inspection
  - Ash Handling System Repair

Assign the following employees to this project:
  - Tyler Moore (EMP019)
  - Lauren Jackson (EMP020)
======================================================
DIRECTIVE

chown ga:ga /home/ga/Desktop/q1_project_restructure.txt
log "Directive document created at ~/Desktop/q1_project_restructure.txt"

# Navigate to the Sentrifugo dashboard
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/projects"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

log "Task setup complete. Agent can begin."