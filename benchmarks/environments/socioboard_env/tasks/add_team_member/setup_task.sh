#!/bin/bash
echo "=== Setting up add_team_member task ==="

source /workspace/scripts/task_utils.sh

# Remove any root-owned tmp files from previous runs that would block writes
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

TEAM_NAME="Content Strategy Team"

# ============================================================
# Pre-create the "Content Strategy Team" via API
# CRITICAL: Use Python tempfile for JSON body to avoid bash !-expansion issue
# CRITICAL: Correct API format is {"TeamInfo": {"name": "...", "description": "..."}}
# CRITICAL: Endpoint is POST /v1/team/create with x-access-token header
# ============================================================
log "Setting up '${TEAM_NAME}' team..."

# Clean up any existing team member records for a fresh state
# (Remove previous test runs so verifier can detect the new invite)
mysql -u root "$DB_NAME" -e "
  DELETE jt FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = '${TEAM_NAME}'
    AND jt.user_id != (SELECT user_id FROM user_details WHERE email = '${ADMIN_EMAIL}' LIMIT 1)
" 2>/dev/null || true

# Remove existing team (so we can recreate fresh)
mysql -u root "$DB_NAME" -e "
  DELETE FROM join_table_users_teams WHERE team_id IN
    (SELECT team_id FROM team_informations WHERE team_name = '${TEAM_NAME}')
" 2>/dev/null || true
mysql -u root "$DB_NAME" -e "
  DELETE FROM team_informations WHERE team_name = '${TEAM_NAME}'
" 2>/dev/null || true

# Create the team via API using Python (avoids bash ! expansion issue)
log "Creating '${TEAM_NAME}' via API..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

admin_email = "admin@socioboard.local"
admin_pass = "Admin2024!"
team_name = "Content Strategy Team"

# Step 1: Login
login_body = {"user": admin_email, "password": admin_pass}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(login_body, f)
    login_tmp = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json',
     '-d', '@' + login_tmp, 'http://127.0.0.1:3000/v1/login'],
    capture_output=True, text=True, timeout=30
)
os.unlink(login_tmp)

try:
    login_data = json.loads(result.stdout)
    token = login_data.get('accessToken', '')
except Exception as e:
    print(f"Login failed: {e}, stdout: {result.stdout[:200]}", file=sys.stderr)
    sys.exit(1)

if not token:
    print(f"No token in login response: {result.stdout[:200]}", file=sys.stderr)
    sys.exit(1)

print(f"Login OK, token: {token[:30]}...")

# Step 2: Create team
# CRITICAL: API expects {"TeamInfo": {"name": "...", "description": "..."}}
team_body = {"TeamInfo": {"name": team_name, "description": "Content strategy and planning"}}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(team_body, f)
    team_tmp = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'POST',
     '-H', 'Content-Type: application/json',
     '-H', 'x-access-token: ' + token,
     '-d', '@' + team_tmp,
     'http://127.0.0.1:3000/v1/team/create'],
    capture_output=True, text=True, timeout=30
)
os.unlink(team_tmp)
print(f"Team create response: {result.stdout[:300]}")

try:
    resp = json.loads(result.stdout)
    if resp.get('code') == 200:
        print(f"Team '{team_name}' created with ID: {resp.get('teamDetails', {}).get('team_id')}")
    elif resp.get('code') == 400:
        print(f"Team already exists (code 400) - that is OK")
    else:
        print(f"Unexpected response: {resp}", file=sys.stderr)
except Exception as e:
    print(f"Could not parse team response: {e}", file=sys.stderr)
PYEOF

TEAM_EXISTS=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM team_informations WHERE team_name = '${TEAM_NAME}'
" 2>/dev/null || echo "0")

if [ "$TEAM_EXISTS" = "0" ] || [ -z "$TEAM_EXISTS" ]; then
  log "WARNING: Team still not found in DB after API call"
else
  log "Team '${TEAM_NAME}' confirmed in database"
fi

# ============================================================
# Ensure John Smith user exists (pre-created during setup)
# ============================================================
JOHN_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$JOHN_ID" ]; then
  log "John Smith not found, creating via API..."
  python3 << 'PYPEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "johnsmith",
        "email": "john.smith@socioboard.local",
        "password": "User2024!",
        "firstName": "John",
        "lastName": "Smith",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/johnsmith",
        "dateOfBirth": "1985-06-15",
        "phoneCode": "+1",
        "phoneNo": "5550000002",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Team member"
    }
}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(body, f)
    tmpfile = f.name

result = subprocess.run(
    ['curl', '-s', '-X', 'PUT', '-H', 'Content-Type: application/json',
     '-d', '@' + tmpfile, 'http://127.0.0.1:3000/v1/register'],
    capture_output=True, text=True, timeout=30
)
os.unlink(tmpfile)
print(f"John Smith register: {result.stdout[:200]}")
PYPEOF

  # Activate
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1
  " 2>/dev/null || true
fi

log "John Smith user ready (ID: ${JOHN_ID:-newly created})"

# ============================================================
# Wait for Socioboard to be ready and open login page
# ============================================================
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

# Clear any existing session by navigating to logout first
log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

# Open Socioboard login page (agent will see login form)
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete: add_team_member ==="
