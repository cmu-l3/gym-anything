#!/bin/bash
set -e
echo "=== Setting up create_incident_bookmarks task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Ensure Nx Server is up and we have a valid token
refresh_nx_token > /dev/null
TOKEN=$(get_nx_token)

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Clean up existing bookmarks to ensure a fresh state
echo "Cleaning existing bookmarks..."
EXISTING_BOOKMARKS=$(curl -sk "${NX_BASE}/rest/v1/bookmarks" -H "Authorization: Bearer ${TOKEN}" 2>/dev/null || echo "[]")

# Parse and delete each bookmark
echo "$EXISTING_BOOKMARKS" | python3 -c "
import sys, json
try:
    bookmarks = json.load(sys.stdin)
    for b in bookmarks:
        print(b.get('id', ''))
except:
    pass
" | while read -r bid; do
    if [ -n "$bid" ]; then
        echo "Deleting bookmark $bid"
        curl -sk -X DELETE "${NX_BASE}/rest/v1/bookmarks/${bid}" -H "Authorization: Bearer ${TOKEN}"
    fi
done

# 4. Verify count is zero
INITIAL_COUNT=$(curl -sk "${NX_BASE}/rest/v1/bookmarks" -H "Authorization: Bearer ${TOKEN}" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_bookmark_count.txt
echo "Initial bookmark count: $INITIAL_COUNT"

# 5. Generate Incident Base Timestamp
# Set it to 30 minutes ago (1800000 ms)
CURRENT_MS=$(date +%s%3N)
INCIDENT_MS=$((CURRENT_MS - 1800000))

echo "$INCIDENT_MS" > /home/ga/incident_start_time.txt
chown ga:ga /home/ga/incident_start_time.txt

echo "Incident base time set to: $INCIDENT_MS"
echo "Instructions for Agent:"
echo "  - Read base time from: /home/ga/incident_start_time.txt"
echo "  - Create bookmarks relative to this time."

# 6. Take initial screenshot (of empty terminal/desktop, mainly for protocol)
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="