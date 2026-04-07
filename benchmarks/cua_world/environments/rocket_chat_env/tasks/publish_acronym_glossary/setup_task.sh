#!/bin/bash
set -euo pipefail

echo "=== Setting up publish_acronym_glossary task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
rm -f /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# Create the real CSV data file
mkdir -p /home/ga/Documents
CSV_FILE="/home/ga/Documents/acronyms.csv"

cat > "$CSV_FILE" << 'EOF'
Acronym,Definition
API,Application Programming Interface
CI,Continuous Integration
CD,Continuous Deployment
JSON,JavaScript Object Notation
RBAC,Role-Based Access Control
SaaS,Software as a Service
SSH,Secure Shell
SSL,Secure Sockets Layer
TDD,Test-Driven Development
UI,User Interface
UX,User Experience
VPN,Virtual Private Network
EOF

chown ga:ga "$CSV_FILE"

# Verify Rocket.Chat API is reachable
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable at ${ROCKETCHAT_BASE_URL}"
  exit 1
fi

# Verify login credentials work
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

if ! api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
  echo "ERROR: Task login credentials are not valid yet"
  exit 1
fi

# Clean state: remove the glossary channel if it already exists from a previous run
# We use docker exec to mongosh to ensure a completely clean slate
echo "Removing any pre-existing glossary channel..."
docker exec rc-mongodb mongosh --quiet "mongodb://localhost:27017/rocketchat?directConnection=true" \
  --eval 'db.rocketchat_room.deleteMany({name: "glossary", t: "c"});' 2>/dev/null || true

# Start Firefox at Rocket.Chat login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start cleanly"
  DISPLAY=:1 wmctrl -l 2>/dev/null || true
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

# Take initial screenshot for evidence
take_screenshot /tmp/task_start.png

echo "Task start screenshot: /tmp/task_start.png"
echo "=== Task setup complete ==="