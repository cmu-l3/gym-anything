#!/bin/bash
echo "=== Exporting event_promotion_coordination result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/event_promotion_end.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Profile
PROFILE=$(mysql -u root "$DB_NAME" -N -B -e "
  SELECT first_name, last_name, about_me, phone_no, phone_code, time_zone
  FROM user_details WHERE email = '${ADMIN_EMAIL}' LIMIT 1
" 2>/dev/null || echo "")

# Teams
TEAMS_JSON="["
FIRST=true
for TEAM in "TechSummit 2026 - Pre-Event Buzz" "TechSummit 2026 - Live Coverage" "TechSummit 2026 - Post-Event Engagement"; do
  EXISTS=$(mysql -u root "$DB_NAME" -N -e "
    SELECT COUNT(*) FROM team_informations WHERE team_name = '${TEAM}'
  " 2>/dev/null || echo "0")
  if [ "$FIRST" = true ]; then FIRST=false; else TEAMS_JSON="${TEAMS_JSON},"; fi
  TEAMS_JSON="${TEAMS_JSON}{\"name\":\"${TEAM}\",\"exists\":${EXISTS}}"
done
TEAMS_JSON="${TEAMS_JSON}]"

# john.smith memberships in TechSummit teams
JOHN_MEMBERSHIPS=$(mysql -u root "$DB_NAME" -N -B -e "
  SELECT ti.team_name FROM join_table_users_teams jt
  JOIN team_informations ti ON jt.team_id = ti.team_id
  JOIN user_details ud ON jt.user_id = ud.user_id
  WHERE ud.email = 'john.smith@socioboard.local'
    AND ti.team_name LIKE 'TechSummit%'
" 2>/dev/null || echo "")

# RSS
RSS_BASELINE=$(cat /tmp/rss_log_baseline 2>/dev/null || echo "0")
if [ -f /var/log/apache2/socioboard_access.log ]; then
  RSS_HITS=$(tail -n +"$((RSS_BASELINE + 1))" /var/log/apache2/socioboard_access.log 2>/dev/null | grep -c "POST /getRss" || echo "0")
else
  RSS_HITS=0
fi

cat > /tmp/event_promotion_result.json << EOFRESULT
{
  "task_start": ${TASK_START},
  "profile_raw": "$(echo "$PROFILE" | tr '\t' '|')",
  "teams": ${TEAMS_JSON},
  "john_memberships": "$(echo "$JOHN_MEMBERSHIPS" | tr '\n' '|')",
  "rss_hits": ${RSS_HITS}
}
EOFRESULT

echo "=== Export complete ==="
