#!/bin/bash
echo "=== Setting up HRIS Localization and Security Hardening task ==="

source /workspace/scripts/task_utils.sh
wait_for_http "$SENTRIFUGO_URL" 60

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# ---- Reset State to Prevent Gaming ----
log "Resetting module states to active defaults..."
# Ensure all modules are active initially so the agent must explicitly deactivate the target ones
sentrifugo_db_root_query "UPDATE main_modules SET isactive=1;" 2>/dev/null || true

# ---- Drop the IT Change Request Document ----
mkdir -p /home/ga/Desktop
cat > /home/ga/Desktop/hris_globalization_directive.txt << 'DIRECTIVE'
IT CHANGE REQUEST: HRIS GLOBALIZATION & SECURITY HARDENING
Ticket: REQ-2026-088
Priority: HIGH

Please execute the following global configuration changes in the Sentrifugo HRMS:

1. LOCALIZATION (Site Config > General Settings)
   - Timezone: Europe/Berlin
   - Date Format: DD/MM/YYYY

2. SECURITY HARDENING (Site Config > Password Policy)
   - Minimum Password Length: 12 characters
   - Character Complexity: Enable ALL (Uppercase, Lowercase, Numbers, Special Characters)
   - Password Expiry: 90 days

3. MODULE DEACTIVATION (Site Config > Modules)
   - Deactivate "Assets" (Migrating to ServiceNow)
   - Deactivate "Expenses" (Migrating to Concur)
   - IMPORTANT: Do NOT deactivate any other modules. Core HR functionality must remain active.

Implementation must be completed immediately.
DIRECTIVE

chown ga:ga /home/ga/Desktop/hris_globalization_directive.txt
log "Created IT Change Request directive at ~/Desktop/hris_globalization_directive.txt"

# ---- Ensure login and navigate to dashboard ----
ensure_sentrifugo_logged_in "${SENTRIFUGO_URL}/dashboard"
sleep 3

# Take initial screenshot for evidence
take_screenshot /tmp/task_start_screenshot.png

log "Task ready: directive on Desktop, browser logged in to Sentrifugo"
echo "=== Setup complete ==="