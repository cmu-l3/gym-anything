#!/bin/bash
echo "=== Setting up configure_time_tracking_fields task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Redmine is ready
if ! wait_for_http "$REDMINE_LOGIN_URL" 600; then
  echo "ERROR: Redmine is not reachable"
  exit 1
fi

# Ensure seed data is present to find an issue
if [ ! -f "$SEED_RESULT_FILE" ]; then
  echo "ERROR: Seed result file not found. Redmine setup may be incomplete."
  exit 1
fi

# Pick a specific issue from the seed data to be the target
# We'll look for an issue with a subject we know exists or just pick the first one
TARGET_ISSUE_ID=$(jq -r '.issues[0].id // empty' "$SEED_RESULT_FILE")
TARGET_ISSUE_SUBJECT=$(jq -r '.issues[0].subject // empty' "$SEED_RESULT_FILE")

if [ -z "$TARGET_ISSUE_ID" ]; then
  # Fallback if seed parsing fails, though unlikely
  echo "WARNING: Could not parse issue from seed file. Creating task brief with placeholders."
  TARGET_ISSUE_ID="1"
  TARGET_ISSUE_SUBJECT="Example Issue"
fi

# Create the Task Brief file
cat > /home/ga/task_brief.txt <<EOF
TASK BRIEF
==========
Target Issue ID: $TARGET_ISSUE_ID
Target Subject: $TARGET_ISSUE_SUBJECT

Instructions:
1. Configure the custom fields as described in the task description.
2. Navigate to Issue #$TARGET_ISSUE_ID.
3. Log 4.0 hours of time with the new custom fields.
EOF

chown ga:ga /home/ga/task_brief.txt
chmod 644 /home/ga/task_brief.txt

log "Created task brief for Issue #$TARGET_ISSUE_ID"

# Log in as admin and go to Administration page to start
if ! ensure_redmine_logged_in "$REDMINE_BASE_URL/admin"; then
  echo "ERROR: Failed to log in"
  exit 1
fi

# Dismiss any potential Firefox dialogs/popups
focus_firefox || true
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="