#!/bin/bash
set -e
echo "=== Setting up create_custom_role task ==="

source /workspace/scripts/task_utils.sh

# 1. Create the policy document
mkdir -p /home/ga/Documents
cat > /home/ga/Documents/audit_access_policy.txt << 'EOF'
=== ISO 27001 AUDIT ACCESS POLICY ===
Role Name: External Auditor
Scope: Read-Only Access for Compliance Verification

REQUIRED PERMISSIONS (Enable these):
1. General:
   - View project

2. Issue Tracking:
   - View issues
   - View watchers

3. Documentation:
   - View documents
   - View files

4. Wiki:
   - View wiki pages
   - View wiki history

5. Repository (Code):
   - View changesets
   - Browse repository

RESTRICTED ACTIONS (Ensure these are DISABLED):
- DO NOT allow adding, editing, or deleting issues.
- DO NOT allow logging time or viewing time entries (Financial privacy).
- DO NOT allow posting in forums or news.
EOF

chown ga:ga /home/ga/Documents/audit_access_policy.txt
chmod 644 /home/ga/Documents/audit_access_policy.txt

# 2. Record start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable at $REDMINE_LOGIN_URL"
  exit 1
fi

# 4. Login and prepare browser
# We start at the Administration page to be helpful, but agent must navigate to Roles
TARGET_URL="$REDMINE_BASE_URL/admin"
log "Opening Firefox at: $TARGET_URL"

if ! ensure_redmine_logged_in "$TARGET_URL"; then
  echo "ERROR: Failed to log in to Redmine."
  exit 1
fi

focus_firefox || true
sleep 2

# 5. Capture initial state
take_screenshot /tmp/task_initial.png
log "Task setup complete"