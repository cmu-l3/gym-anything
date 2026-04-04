#!/bin/bash
set -e

echo "=== Setting up import_us_senators_leads task ==="

source /workspace/scripts/task_utils.sh

vicidial_ensure_running

# Ensure the CSV is accessible in the expected path for the agent.
mkdir -p /home/ga/Documents/VicidialData
SRC_CSV="/workspace/assets/us_senators_vicidial_standard_format_list9001_2026-02-14.csv"
DST_CSV="/home/ga/Documents/VicidialData/us_senators_vicidial_standard_format_list9001_2026-02-14.csv"
if [ ! -f "$SRC_CSV" ]; then
  echo "FATAL: missing required asset: $SRC_CSV" >&2
  exit 1
fi
install -m 0644 -o ga -g ga "$SRC_CSV" "$DST_CSV"
chmod 0644 "$DST_CSV" || true
chown -R ga:ga /home/ga/Documents/VicidialData

# Deterministic DB state:
# - ensure admin user can create lists and load leads
# - ensure list 9001 does not already exist (otherwise "create list" fails)
echo "Waiting for Vicidial MySQL to be ready..."
for i in $(seq 1 60); do
  if docker exec vicidial mysql -ucron -p1234 -D asterisk -e "SELECT 1;" >/dev/null 2>&1; then
    echo "Vicidial MySQL is ready"
    break
  fi
  sleep 2
  if [ "$i" -eq 60 ]; then
    echo "WARNING: Vicidial MySQL did not become ready; continuing anyway"
  fi
done

echo "Applying Vicidial permissions for user 6666..."
docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
  "UPDATE vicidial_users SET modify_lists='1', modify_leads='1', modify_campaigns='1', view_reports='1' WHERE user='6666';" \
  >/dev/null 2>&1 || true

echo "Cleaning up list_id=9001 for deterministic task start..."
if docker exec vicidial mysql -ucron -p1234 -D asterisk -N -e "SHOW TABLES LIKE 'vicidial_list_alt_phones';" 2>/dev/null | grep -q vicidial_list_alt_phones; then
  docker exec vicidial mysql -ucron -p1234 -D asterisk -e \
    "DELETE FROM vicidial_list_alt_phones WHERE lead_id IN (SELECT lead_id FROM vicidial_list WHERE list_id='9001');" \
    >/dev/null 2>&1 || true
fi
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_list WHERE list_id='9001';" >/dev/null 2>&1 || true
docker exec vicidial mysql -ucron -p1234 -D asterisk -e "DELETE FROM vicidial_lists WHERE list_id='9001';" >/dev/null 2>&1 || true

# Deterministic start state: restart Firefox and land on the "Add A New List" screen.
# Vicidial is protected by Apache HTTP Basic Auth in this Docker image; pre-authenticate
# so the agent starts on the actual Vicidial page instead of the browser modal dialog.
START_URL="${VICIDIAL_ADMIN_URL}?ADD=111"
pkill -f firefox 2>/dev/null || true
for i in $(seq 1 30); do
  pgrep -f firefox >/dev/null 2>&1 || break
  sleep 1
done
su - ga -c "DISPLAY=:1 firefox --new-window '${START_URL}' > /tmp/firefox_vicidial_task.log 2>&1 &"

wait_for_window "firefox|mozilla|vicidial" 30 || true
focus_firefox
maximize_active_window

echo "Attempting HTTP Basic Auth login in Firefox..."
sleep 1
DISPLAY=:1 xdotool type --delay 50 "6666"
DISPLAY=:1 xdotool key Tab
DISPLAY=:1 xdotool type --delay 50 "andromeda"
DISPLAY=:1 xdotool key Return

# Ensure we are on the intended start URL after authentication.
for i in $(seq 1 60); do
  if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "Add New List"; then
    break
  fi
  [ $((i % 10)) -eq 0 ] && navigate_to_url "$START_URL"
  sleep 1
done

take_screenshot /tmp/task_start.png

echo "=== Task setup complete ==="
