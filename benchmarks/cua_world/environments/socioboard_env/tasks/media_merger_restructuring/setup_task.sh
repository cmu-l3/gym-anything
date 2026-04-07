#!/bin/bash
echo "=== Setting up media_merger_restructuring ==="

source /workspace/scripts/task_utils.sh

# Clean stale artifacts from previous runs
sudo rm -f /tmp/mmr_start_ts /tmp/mmr_rss_baseline /tmp/task_start.png 2>/dev/null || true

# ============================================================
# Inject wrong profile (agent must update to Rachel Torres)
# ============================================================
log "Injecting placeholder profile..."
mysql -u root "$DB_NAME" -e "
  UPDATE user_details SET
    first_name = 'System',
    last_name = 'Administrator',
    about_me = 'Default system account. Awaiting configuration.',
    time_zone = 'UTC',
    phone_no = '0000000000',
    phone_code = '+0'
  WHERE email = '${ADMIN_EMAIL}'
" 2>/dev/null || true

# ============================================================
# Clean up any newsroom teams from previous runs
# ============================================================
log "Cleaning previous newsroom teams..."
for TEAM in "Metro Desk" "State Politics" "Tech & Science" "Arts & Culture" "Sports" "Investigations" "Breaking News"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# Clean any leftover legacy teams from previous runs
mysql -u root "$DB_NAME" -e "
  DELETE FROM join_table_users_teams WHERE team_id IN
    (SELECT team_id FROM team_informations WHERE team_name LIKE '[LEGACY]%')
" 2>/dev/null || true
mysql -u root "$DB_NAME" -e "
  DELETE FROM team_informations WHERE team_name LIKE '[LEGACY]%'
" 2>/dev/null || true

# Clean any leftover safe teams from previous runs
for TEAM in "Daily Briefing" "Weekend Edition"; do
  mysql -u root "$DB_NAME" -e "
    DELETE FROM join_table_users_teams WHERE team_id IN
      (SELECT team_id FROM team_informations WHERE team_name = '${TEAM}')
  " 2>/dev/null || true
  mysql -u root "$DB_NAME" -e "
    DELETE FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || true
done

# ============================================================
# Ensure emily.chen exists
# ============================================================
EMILY_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'emily.chen@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$EMILY_ID" ]; then
  log "Creating emily.chen..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "emilychen",
        "email": "emily.chen@socioboard.local",
        "password": "User2024!",
        "firstName": "Emily",
        "lastName": "Chen",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/emilychen",
        "dateOfBirth": "1990-03-22",
        "phoneCode": "+1",
        "phoneNo": "5550000010",
        "country": "US",
        "timeZone": "America/New_York",
        "aboutMe": "Metro and politics reporter at Cascadia Media Group"
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
print(f"Register emily.chen: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE id = (SELECT user_id FROM user_details WHERE email = 'emily.chen@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Ensure michael.okafor exists
# ============================================================
MICHAEL_ID=$(mysql -u root "$DB_NAME" -N -e "
  SELECT user_id FROM user_details WHERE email = 'michael.okafor@socioboard.local' LIMIT 1
" 2>/dev/null || echo "")

if [ -z "$MICHAEL_ID" ]; then
  log "Creating michael.okafor..."
  python3 << 'PYEOF'
import subprocess, json, tempfile, os

body = {
    "user": {
        "userName": "michaelokafor",
        "email": "michael.okafor@socioboard.local",
        "password": "User2024!",
        "firstName": "Michael",
        "lastName": "Okafor",
        "profilePicture": "https://www.socioboard.com/Content/images/profile-images/default-profile-pic.png",
        "profileUrl": "https://www.socioboard.com/michaelokafor",
        "dateOfBirth": "1988-07-14",
        "phoneCode": "+1",
        "phoneNo": "5550000011",
        "country": "US",
        "timeZone": "America/Chicago",
        "aboutMe": "Technology and culture reporter at Cascadia Media Group"
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
print(f"Register michael.okafor: {result.stdout[:200]}")
PYEOF
  mysql -u root "$DB_NAME" -e "
    UPDATE user_activations SET activation_status = 1, user_plan = 2
    WHERE id = (SELECT user_id FROM user_details WHERE email = 'michael.okafor@socioboard.local')
  " 2>/dev/null || true
fi

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
        "phoneCode": "+1",
        "phoneNo": "5550000012",
        "country": "US",
        "timeZone": "America/Los_Angeles",
        "aboutMe": "Investigations and breaking news reporter at Cascadia Media Group"
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
    WHERE id = (SELECT user_id FROM user_details WHERE email = 'victoria.santos@socioboard.local')
  " 2>/dev/null || true
fi

# ============================================================
# Create [LEGACY] teams (agent must delete these)
# and safe operational teams (agent must NOT delete)
# ============================================================
log "Creating legacy and safe teams via API..."
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
    # [LEGACY] teams -- agent must delete these
    ("[LEGACY] Pacific West Division", "Pacific Coast Digital west region team - legacy"),
    ("[LEGACY] Coastal Features Desk", "Pacific Coast Digital features desk - legacy"),
    ("[LEGACY] Digital Pilot Program", "Pacific Coast Digital pilot initiative - legacy"),
    # Safe operational teams -- agent must NOT delete these
    ("Daily Briefing", "Morning editorial briefing coordination"),
    ("Weekend Edition", "Weekend programming and content planning"),
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
# Record baseline state
# ============================================================
log "Recording baseline state..."

# Count legacy teams (should be 3)
LEGACY_COUNT=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM team_informations WHERE team_name LIKE '[LEGACY]%'
" 2>/dev/null || echo "0")
echo "$LEGACY_COUNT" > /tmp/mmr_legacy_baseline
log "Legacy teams at baseline: $LEGACY_COUNT"

if [ -f /var/log/apache2/socioboard_access.log ]; then
  wc -l < /var/log/apache2/socioboard_access.log > /tmp/mmr_rss_baseline
else
  echo "0" > /tmp/mmr_rss_baseline
fi

date +%s > /tmp/mmr_start_ts

# ============================================================
# Navigate browser to login page
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
echo "=== Setup complete: media_merger_restructuring ==="
