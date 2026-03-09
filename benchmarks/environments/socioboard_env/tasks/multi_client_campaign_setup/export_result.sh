#!/bin/bash
echo "=== Exporting multi_client_campaign_setup result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/multi_client_campaign_setup_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ============================================================
# Query profile state
# ============================================================
PROFILE=$(mysql -u root "$DB_NAME" -N -B -e "
  SELECT first_name, last_name, about_me, phone_no, phone_code, time_zone
  FROM user_details WHERE email = '${ADMIN_EMAIL}' LIMIT 1
" 2>/dev/null || echo "")

# ============================================================
# Query team existence
# ============================================================
TEAMS_JSON="["
FIRST=true
for TEAM in "GlobalTech - Paid Social" "GlobalTech - Organic Content" "GlobalTech - Influencer Outreach" "GlobalTech - Performance Analytics"; do
  EXISTS=$(mysql -u root "$DB_NAME" -N -e "
    SELECT COUNT(*) FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || echo "0")
  if [ "$FIRST" = true ]; then FIRST=false; else TEAMS_JSON="${TEAMS_JSON},"; fi
  TEAMS_JSON="${TEAMS_JSON}{\"name\":\"${TEAM}\",\"exists\":${EXISTS}}"
done
TEAMS_JSON="${TEAMS_JSON}]"

# ============================================================
# Query john.smith memberships
# ============================================================
JOHN_MEMBERSHIPS=$(mysql -u root "$DB_NAME" -N -B -e "
  SELECT ti.team_name
  FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  JOIN user_details ud ON jt.user_id = ud.user_id
  WHERE ud.email = 'john.smith@socioboard.local'
    AND ti.team_name LIKE 'GlobalTech%'
" 2>/dev/null || echo "")

# ============================================================
# Check contaminator teams
# ============================================================
CONTAM1_NOW=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Old Campaign Draft'
" 2>/dev/null || echo "0")

CONTAM2_NOW=$(mysql -u root "$DB_NAME" -N -e "
  SELECT COUNT(*) FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  WHERE ti.team_name = 'Test Team DELETE ME'
" 2>/dev/null || echo "0")

CONTAM1_BASE=$(cat /tmp/contam1_baseline 2>/dev/null || echo "0")
CONTAM2_BASE=$(cat /tmp/contam2_baseline 2>/dev/null || echo "0")

# ============================================================
# Check RSS activity
# ============================================================
RSS_BASELINE=$(cat /tmp/rss_log_baseline 2>/dev/null || echo "0")
if [ -f /var/log/apache2/socioboard_access.log ]; then
  RSS_HITS=$(tail -n +"$((RSS_BASELINE + 1))" /var/log/apache2/socioboard_access.log 2>/dev/null | grep -c "POST /getRss" || echo "0")
else
  RSS_HITS=0
fi

cat > /tmp/multi_client_campaign_setup_result.json << EOFRESULT
{
  "task_start": ${TASK_START},
  "profile_raw": "$(echo "$PROFILE" | tr '\t' '|')",
  "teams": ${TEAMS_JSON},
  "john_memberships": "$(echo "$JOHN_MEMBERSHIPS" | tr '\n' '|')",
  "contam1_baseline": ${CONTAM1_BASE},
  "contam1_now": ${CONTAM1_NOW},
  "contam2_baseline": ${CONTAM2_BASE},
  "contam2_now": ${CONTAM2_NOW},
  "rss_hits": ${RSS_HITS}
}
EOFRESULT

echo "=== Export complete ==="
