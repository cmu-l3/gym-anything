#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up Configure Priority Matrix Task ==="

# 1. Record Task Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure ServiceDesk Plus is running (waits for install if needed)
ensure_sdp_running

# 3. Capture Initial Priority Matrix State
# We query the DB to get the current state before the agent touches it.
# This allows us to verify that the agent actually *changed* something.
echo "Recording initial matrix state..."

SQL_QUERY="SELECT i.name as impact, u.name as urgency, p.name as priority 
FROM prioritymatrix pm 
JOIN impact i ON pm.impactid = i.impactid 
JOIN urgency u ON pm.urgencyid = u.urgencyid 
JOIN priority p ON pm.priorityid = p.priorityid 
ORDER BY i.name, u.name;"

# Execute query using task_utils helper
# Output format: impact|urgency|priority (one per line)
INITIAL_STATE=$(sdp_db_exec "$SQL_QUERY" "servicedesk")

# Save to temp file
cat > /tmp/initial_matrix_state.txt <<EOF
$INITIAL_STATE
EOF

echo "Initial state captured ($(wc -l < /tmp/initial_matrix_state.txt) rows)."

# 4. Prepare Browser
# Open Firefox to the login page
ensure_firefox_on_sdp "${SDP_BASE_URL}/ManageEngine/Login.do"
sleep 5

# 5. Take Initial Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="