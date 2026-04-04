#!/bin/bash
set -e
echo "=== Setting up optimize_virtual_repo_order task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Artifactory to be ready
if ! wait_for_artifactory 120; then
    echo "ERROR: Artifactory did not start in time"
    exit 1
fi

# 2. Cleanup existing repositories to ensure clean state
echo "Cleaning up old repositories..."
delete_repo_if_exists "team-virtual"
delete_repo_if_exists "team-remote"
delete_repo_if_exists "team-local"

# 3. Create Repositories via REST API
# Note: Admin credentials are used (admin:password)

# Create Local Repository: team-local
echo "Creating team-local..."
art_api PUT "/api/repositories/team-local" '{
  "key": "team-local",
  "rclass": "local",
  "packageType": "maven",
  "description": "Local artifacts for the team",
  "repoLayoutRef": "maven-2-default"
}'

# Create Remote Repository: team-remote
echo "Creating team-remote..."
art_api PUT "/api/repositories/team-remote" '{
  "key": "team-remote",
  "rclass": "remote",
  "packageType": "maven",
  "url": "https://repo1.maven.org/maven2/",
  "description": "Proxy for Maven Central",
  "repoLayoutRef": "maven-2-default"
}'

# Create Virtual Repository: team-virtual (INTENTIONALLY MISCONFIGURED ORDER)
# Order: team-remote (first), team-local (second)
echo "Creating team-virtual with suboptimal order..."
art_api PUT "/api/repositories/team-virtual" '{
  "key": "team-virtual",
  "rclass": "virtual",
  "packageType": "maven",
  "repositories": ["team-remote", "team-local"],
  "description": "Team Virtual Repo",
  "repoLayoutRef": "maven-2-default"
}'

# 4. Verify Setup
echo "Verifying initial state..."
CONFIG=$(art_api GET "/api/repositories/team-virtual")
ORDER=$(echo "$CONFIG" | python3 -c "import sys, json; print(json.load(sys.stdin).get('repositories', []))")
echo "Initial Order: $ORDER"

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 5. UI Setup
# Ensure Firefox is running and navigate to the virtual repo configuration page
# This helps the agent start right where the problem is, or at least in the admin area
REPO_EDIT_URL="http://localhost:8082/ui/admin/repositories/virtual/team-virtual"

echo "Launching Firefox..."
ensure_firefox_running "http://localhost:8082"
sleep 5
navigate_to "$REPO_EDIT_URL"

# Dismiss any potential popups/alerts by pressing Escape
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize window
DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="