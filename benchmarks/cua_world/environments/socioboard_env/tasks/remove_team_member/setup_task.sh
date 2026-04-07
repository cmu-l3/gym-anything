#!/bin/bash
echo "=== Setting up remove_team_member task ==="

source /workspace/scripts/task_utils.sh

TEAM_NAME="Content Creators"
TAYLOR_EMAIL="taylor@socioboard.local"

# Remove any root-owned tmp files from previous runs
sudo rm -f /tmp/task_start_timestamp /tmp/task_start.png /tmp/remove_team_member_result.json 2>/dev/null || true
date +%s > /tmp/task_start_timestamp

# ============================================================
# 1. Clean up existing data for fresh setup
# ============================================================
log "Cleaning up existing team and user data..."
mysql -u root "$DB_NAME" -e "
  DELETE jt FROM join_table_users_teams jt JOIN user_details ud ON jt.user_id = ud.user_id WHERE ud.email = '${TAYLOR_EMAIL}';
  DELETE FROM user_details WHERE email = '${TAYLOR_EMAIL}';
  DELETE FROM join_table_users_teams WHERE team_id IN (SELECT team_id FROM team_informations WHERE team_name = '${TEAM_NAME}');
  DELETE FROM team_informations WHERE team_name = '${TEAM_NAME}';
" 2>/dev/null || true

# ============================================================
# 2. Create User and Team via API
# ============================================================
log "Creating '${TEAM_NAME}' and user '${TAYLOR_EMAIL}' via API..."

python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

admin_email = "admin@socioboard.local"
admin_pass = "Admin2024!"
team_name = "Content Creators"

# Create User Taylor
body = {
    "user": {
        "userName": "taylormartinez",
        "email": "taylor@socioboard.local",
        "password": "User2024!",
        "firstName": "Taylor",
        "lastName": "Martinez",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/taylormartinez",
        "dateOfBirth": "1990-01-01",
        "phoneCode": "+1",
        "phoneNo": "5550000003",
        "country": "United States",
        "aboutMe": "Content Creator Intern"
    }
}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(body, f)
    user_tmp = f.name

subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', '@' + user_tmp, 'http://127.0.0.1:3000/v1/user/register'], capture_output=True)
os.unlink(user_tmp)

# Login Admin
login_body = {"user": admin_email, "password": admin_pass}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(login_body, f)
    login_tmp = f.name

res = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json', '-d', '@' + login_tmp, 'http://127.0.0.1:3000/v1/login'], capture_output=True, text=True)
os.unlink(login_tmp)

try:
    token = json.loads(res.stdout).get('accessToken', '')
except:
    print("Failed to get access token.")
    sys.exit(1)

# Create Team
team_body = {"TeamInfo": {"name": team_name, "description": "Content creation and social media management"}}
with tempfile.NamedTemporaryFile(mode='w', suffix='.json', delete=False) as f:
    json.dump(team_body, f)
    team_tmp = f.name

subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Content-Type: application/json', '-H', 'x-access-token: ' + token, '-d', '@' + team_tmp, 'http://127.0.0.1:3000/v1/team/create'], capture_output=True)
os.unlink(team_tmp)
PYEOF

# ============================================================
# 3. Add Taylor to the Content Creators Team (Direct DB Insert)
# ============================================================
TEAM_ID=$(mysql -u root "$DB_NAME" -N -e "SELECT team_id FROM team_informations WHERE team_name = '${TEAM_NAME}' LIMIT 1" 2>/dev/null)
TAYLOR_ID=$(mysql -u root "$DB_NAME" -N -e "SELECT user_id FROM user_details WHERE email = '${TAYLOR_EMAIL}' LIMIT 1" 2>/dev/null)

if [ -n "$TEAM_ID" ] && [ -n "$TAYLOR_ID" ]; then
  log "Adding Taylor (ID: $TAYLOR_ID) to Team (ID: $TEAM_ID)..."
  mysql -u root "$DB_NAME" -e "
    INSERT IGNORE INTO join_table_users_teams (user_id, team_id, invitation_accepted, left_team, created_date) 
    VALUES ($TAYLOR_ID, $TEAM_ID, 1, 0, NOW())
  " 2>/dev/null || true
else
  log "WARNING: Failed to retrieve Team ID or Taylor ID. Setup may be incomplete."
fi

# ============================================================
# 4. Prepare Browser State
# ============================================================
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

log "Clearing browser session via logout..."
open_socioboard_page "http://localhost/logout"
sleep 2

log "Navigating to login page..."
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved: /tmp/task_start.png"
echo "=== Task setup complete: remove_team_member ==="