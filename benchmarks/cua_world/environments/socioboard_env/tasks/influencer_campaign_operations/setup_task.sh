#!/bin/bash
echo "=== Setting up influencer_campaign_operations ==="

source /workspace/scripts/task_utils.sh

# Clean stale artifacts
sudo rm -f /tmp/ico_start_ts /tmp/ico_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject wrong profile data
# ============================================================
log "Injecting wrong profile..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'Casey',
    last_name = 'Thornton',
    about_me = 'Previous account director. Account being transferred.',
    time_zone = 'America/Los_Angeles',
    phone_no = '1111111111',
    phone_code = '+1'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any client teams from previous runs
# ============================================================
log "Cleaning previous client teams..."
for TEAM in "TechFlow Solutions" "NovaBrand Retail" "GreenPath Sustainability" "MediaCraft Studios" "SportsPulse Network"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

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
        "aboutMe": "Media buying coordinator"
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
# Ensure alex.rivera exists
# ============================================================
ALEX_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'alex.rivera@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$ALEX_ID" ]; then
  log "Creating alex.rivera..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "alexrivera",
        "email": "alex.rivera@socioboard.local",
        "password": "User2024!",
        "firstName": "Alex",
        "lastName": "Rivera",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/alexrivera",
        "dateOfBirth": "1987-11-03",
        "phoneCode": "+1",
        "phoneNo": "5550000030",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Agency team lead - technology and consumer brands"
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
print(f"Register alex.rivera: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'alex.rivera@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Ensure priya.nair exists
# ============================================================
PRIYA_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'priya.nair@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$PRIYA_ID" ]; then
  log "Creating priya.nair..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "priyanair",
        "email": "priya.nair@socioboard.local",
        "password": "User2024!",
        "firstName": "Priya",
        "lastName": "Nair",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/priyanair",
        "dateOfBirth": "1991-08-19",
        "phoneCode": "+1",
        "phoneNo": "5550000031",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Agency team lead - media and entertainment"
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
print(f"Register priya.nair: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE user_id = (SELECT user_id FROM user_details WHERE email = 'priya.nair@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Create contaminator teams (Q1 client teams that must persist)
# ============================================================
log "Creating Q1 contaminator teams..."
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

for team_name, desc in [
    ("Q1 - Luminary Fashion", "Q1 2024 retained client - fashion brand"),
    ("Q1 - BrewCo Beverages", "Q1 2024 retained client - beverages"),
    ("Q1 - Atlas Automotive", "Q1 2024 retained client - automotive")
]:
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
    print(f"Contaminator '{team_name}': {result.stdout[:100]}")
PYEOF

# ============================================================
# Record baseline
# ============================================================
log "Recording baseline..."

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/ico_rss_baseline
else
  echo "0" > /tmp/ico_rss_baseline
fi

date +%s > /tmp/ico_start_ts

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
echo "=== Setup complete: influencer_campaign_operations ==="
