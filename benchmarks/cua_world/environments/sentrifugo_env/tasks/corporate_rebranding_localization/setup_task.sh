#!/bin/bash
echo "=== Setting up corporate_rebranding_localization task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time
TASK_START=$(date +%s)
echo "$TASK_START" > /tmp/task_start_timestamp

# ---- Prepare initial DB state ----
log "Setting legacy US organization data..."
# Set global organization to US defaults
sentrifugo_db_root_query "UPDATE main_organization SET orgname='Sentrifugo US', orgcode='S-US', timezone='America/New_York', dateformat='m/d/Y' WHERE id=1;" 2>/dev/null || true

log "Setting legacy US location data..."
# Set default location to New York
sentrifugo_db_root_query "UPDATE main_locations SET locationname='New York HQ', city='New York', timezone='America/New_York', isactive=1 WHERE id=1;" 2>/dev/null || true

# Remove any existing London locations from prior runs
sentrifugo_db_root_query "DELETE FROM main_locations WHERE locationname LIKE '%London%';" 2>/dev/null || true

# ---- Drop transition directive on Desktop ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/uk_transition_directive.txt << 'DIRECTIVE'
ACME GLOBAL TECHNOLOGIES
Post-Acquisition System Localization Directive
Issued by: Global HR Steering Committee
==============================================

Following our acquisition by EcoPower Energy, our primary HRMS instance must be
rebranded and localized for our new UK-based parent company immediately.

ACTION 1: UPDATE GLOBAL ORGANIZATION INFO
-----------------------------------------
Update the global organization details in the HRMS:
- Organization Name : EcoPower Energy UK
- Organization Code : ECO-UK
- Timezone          : Europe/London
- Date Format       : UK Standard (Day/Month/Year)

ACTION 2: CREATE NEW HEADQUARTERS
-----------------------------------------
Create the new primary location record in the system:
- Location Name     : London Global HQ
- City              : London
- Country           : United Kingdom
- Zip Code          : EC1A 1BB
- Timezone          : Europe/London

ACTION 3: DEACTIVATE LEGACY HEADQUARTERS
-----------------------------------------
The former headquarters ("New York HQ") is no longer our primary location.
Deactivate this location in the system. Do NOT delete the record, as it is tied
to historical employee data. Simply change its status to inactive.

==============================================
Please ensure all changes are saved.
DIRECTIVE

chown ga:ga /home/ga/Desktop/uk_transition_directive.txt
log "Transition directive created at ~/Desktop/uk_transition_directive.txt"

# ---- Ensure logged in to Sentrifugo dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_initial.png ga

log "Task setup complete. Sentrifugo is configured as US entity, directive is on Desktop."
echo "=== Setup Complete ==="