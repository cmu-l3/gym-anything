#!/bin/bash
echo "=== Setting up crisis_comms_rapid_response ==="

source /workspace/scripts/task_utils.sh

# Clean stale artifacts
sudo rm -f /tmp/ccr_start_ts /tmp/ccr_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject wrong profile
# ============================================================
log "Injecting wrong profile..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Temp',
    last_name = 'Account',
    about_me = 'Agency account placeholder. Needs update.',
    time_zone = 'America/New_York',
    phone_no = '0000000000',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any crisis teams from previous runs
# ============================================================
log "Cleaning previous crisis teams..."
for TEAM in "Crisis: Media Monitoring" "Crisis: Social Sentiment" "Crisis: Executive Briefing"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# Also clean any leftover archived teams from previous runs
mysql -u root "$DB_NAME" -e "
  DELETE FROM join_table_users_teams WHERE team_id IN
    (SELECT team_id FROM team_informations WHERE team_name LIKE '[ARCHIVED]%')
" 2>/dev/null || true
mysql -u root "$DB_NAME" -e "
  DELETE FROM team_informations WHERE team_name LIKE '[ARCHIVED]%'
" 2>/dev/null || true

# ============================================================
# Ensure victoria.santos exists
# ============================================================
VIC_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'victoria.santos@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$VIC_ID" ]; then
  log "Creating victoria.santos..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "victoriasantos",
        "email": "victoria.santos@socioboard.local",
        "password": "User2024!",
        "firstName": "Victoria",
        "lastName": "Santos",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/victoriasantos",
        "dateOfBirth": "1986-04-08",
        "phoneCode": "+44",
        "phoneNo": "7700900100",
        "country": "GB",
        "timeZone": "Europe/London",
        "aboutMe": "Crisis communications lead at Meridian PR"
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
print(f"Register victoria.santos: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'victoria.santos@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Ensure john.smith exists
# ============================================================
JOHN_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$JOHN_ID" ]; then
  log "Creating john.smith..."
  python3 << 'PYEOF'
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
        "aboutMe": "PR monitoring specialist"
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
print(f"Register john.smith: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'john.smith@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Create the [ARCHIVED] teams (agent must delete these)
# and the "safe" normal teams (agent must NOT delete)
# ============================================================
log "Creating archived and safe teams via API..."
python3 << 'PYEOF'
import subprocess, json, tempfile, os, sys

login_body = {"user": "admin@socioboard.local", "password": "Admin2024!"}
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
    token = json.loads(result.stdout).get('accessToken', '')
except Exception:
    token = ''

if not token:
    print(f"No token: {result.stdout[:200]}", file=sys.stderr)
    sys.exit(0)

all_teams = [
    # [ARCHIVED] teams — agent must delete
    ("[ARCHIVED] Seasonal Campaign Q3", "Legacy Q3 campaign — archived"),
    ("[ARCHIVED] Product Launch Beta", "Beta product launch team — archived"),
    ("[ARCHIVED] Regional Partnership West", "West coast partnership — archived"),
    ("[ARCHIVED] Trade Show Presence", "Trade show team — archived"),
    # Safe teams — agent must NOT delete
    ("Brand Monitoring", "Ongoing brand health monitoring"),
    ("Media Relations", "Press and media relationship management"),
    ("Social Listening", "Real-time social listening"),
    ("Executive Comms", "C-suite communications"),
    ("Internal Comms", "Internal stakeholder communications"),
    ("Influencer Network", "Influencer relationship management"),
]

for team_name, desc in all_teams:
    existing = subprocess.run(
        ['mysql', '-u', 'root', 'socioboard', '-N', '-e',
         f"SELECT COUNT(*) FROM team_informations WHERE team_name='{team_name}'"],
        capture_output=True, text=True
    )
    if existing.stdout.strip() == '1':
        print(f"'{team_name}' already exists")
        continue

    team_body = {"TeamInfo": {"name": team_name, "description": desc}}
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
    print(f"Team '{team_name}': {result.stdout[:80]}")
PYEOF

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

# Count archived teams (should be 4)
ARCHIVED_COUNT=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM team_informations WHERE team_name LIKE '[ARCHIVED]%'
" 2>/dev/null || echo "0")
echo "$ARCHIVED_COUNT" > /tmp/ccr_archived_baseline
log "Archived teams at baseline: $ARCHIVED_COUNT"

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/ccr_rss_baseline
else
  echo "0" > /tmp/ccr_rss_baseline
fi

date +%s > /tmp/ccr_start_ts

# ============================================================
# Navigate to login
# ============================================================
if ! wait_for_http "http://localhost/" 120; then
  echo "ERROR: Socioboard not reachable"
  exit 1
fi

log "Clearing browser session..."
open_socioboard_page "http://localhost/logout"
sleep 2
navigate_to "http://localhost/login"
sleep 3

take_screenshot /tmp/task_start.png
log "Task start screenshot saved"
echo "=== Setup complete: crisis_comms_rapid_response ==="
