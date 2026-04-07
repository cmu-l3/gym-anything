#!/bin/bash
echo "=== Setting up talent_acquisition_pipeline_setup task ==="

source /workspace/scripts/task_utils.sh

# Wait for Sentrifugo to be ready
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming measures
date +%s > /tmp/task_start_time.txt

# ---- Clean up prior run artifacts ----
log "Cleaning up prior run artifacts..."

# Remove potential existing Job Titles
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename LIKE '%Biomass%';" 2>/dev/null || true
sentrifugo_db_root_query "DELETE FROM main_jobtitles WHERE jobtitlename LIKE '%Safety Inspector%';" 2>/dev/null || true

# Try to clean interview rounds safely if table exists in this version's schema
INT_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SHOW TABLES LIKE '%interview%round%';" | head -1)
if [ -n "$INT_TABLE" ]; then
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $INT_TABLE WHERE roundname LIKE '%Phone Screen%';" 2>/dev/null || true
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $INT_TABLE WHERE roundname LIKE '%Technical Plant%';" 2>/dev/null || true
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $INT_TABLE WHERE roundname LIKE '%Manager Interview%';" 2>/dev/null || true
fi

# Try to clean requisitions that may have orphaned job titles
REQ_TABLE=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SHOW TABLES LIKE '%requisition%';" | head -1)
if [ -n "$REQ_TABLE" ]; then
    docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "DELETE FROM $REQ_TABLE WHERE jobtitle_id NOT IN (SELECT id FROM main_jobtitles);" 2>/dev/null || true
fi

# ---- Drop hiring plan on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/q2_hiring_plan.txt << 'PLAN'
=============================================================
        Q2 EXPANSION - HIRING REQUISITIONS & PIPELINE
        Location: Biomass Plant Alpha
=============================================================

STEP 1: NEW JOB TITLES
Please ensure the following Job Titles exist in the system 
before opening the requisitions:
  1. Senior Biomass Process Engineer
  2. Field Safety Inspector

STEP 2: STANDARDIZE INTERVIEW PIPELINE
Add the following Interview Rounds to the Talent Acquisition configuration:
  - Initial Phone Screen
  - Technical Plant Assessment
  - Plant Manager Interview

STEP 3: JOB REQUISITIONS
Open the following two Job Requisitions:

Requisition 1:
  - Job Title: Senior Biomass Process Engineer
  - Department: Engineering
  - Number of Positions: 2
  - Job Type: Full Time

Requisition 2:
  - Job Title: Field Safety Inspector
  - Department: Quality Assurance
  - Number of Positions: 3
  - Job Type: Full Time

=============================================================
Ensure all entries are marked as 'Active' or saved correctly.
PLAN

chown ga:ga /home/ga/Desktop/q2_hiring_plan.txt
log "Hiring plan created at ~/Desktop/q2_hiring_plan.txt"

# ---- Ensure login and navigate to dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3
take_screenshot /tmp/task_initial.png

log "Task ready"
echo "=== Setup complete ==="