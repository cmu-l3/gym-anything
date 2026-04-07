#!/bin/bash
echo "=== Exporting departmental_license_reallocation results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

LIC_ADOBE=$(cat /tmp/license_adobe_id.txt 2>/dev/null || echo "0")
LIC_MS365=$(cat /tmp/license_ms365_id.txt 2>/dev/null || echo "0")

# Fallbacks if text files are missing/empty
if [ "$LIC_ADOBE" = "0" ] || [ -z "$LIC_ADOBE" ]; then
    LIC_ADOBE=$(snipeit_db_query "SELECT id FROM licenses WHERE name='Adobe Creative Cloud All Apps' LIMIT 1" | tr -d '[:space:]')
fi
if [ "$LIC_MS365" = "0" ] || [ -z "$LIC_MS365" ]; then
    LIC_MS365=$(snipeit_db_query "SELECT id FROM licenses WHERE name='Microsoft 365' LIMIT 1" | tr -d '[:space:]')
fi

# Adobe verification data
ADOBE_TOTAL_SEATS=$(snipeit_db_query "SELECT seats FROM licenses WHERE id=$LIC_ADOBE" | tr -d '[:space:]' || echo "0")

# Count how many seats are still assigned to unauthorized departments
UNAUTH_COUNT=$(snipeit_db_query "SELECT COUNT(*) FROM license_seats ls JOIN users u ON ls.assigned_to = u.id JOIN departments d ON u.department_id = d.id WHERE ls.license_id=$LIC_ADOBE AND d.name IN ('Sales', 'Finance', 'HR') AND ls.assigned_to IS NOT NULL" | tr -d '[:space:]' || echo "0")

# Total users existing in authorized departments
AUTH_USERS_TOTAL=$(snipeit_db_query "SELECT COUNT(*) FROM users u JOIN departments d ON u.department_id = d.id WHERE d.name IN ('Creative', 'Marketing') AND u.deleted_at IS NULL" | tr -d '[:space:]' || echo "0")

# Count how many seats are checked out to authorized departments
AUTH_CHECKOUT_COUNT=$(snipeit_db_query "SELECT COUNT(DISTINCT ls.assigned_to) FROM license_seats ls JOIN users u ON ls.assigned_to = u.id JOIN departments d ON u.department_id = d.id WHERE ls.license_id=$LIC_ADOBE AND d.name IN ('Creative', 'Marketing') AND ls.assigned_to IS NOT NULL" | tr -d '[:space:]' || echo "0")

# MS365 verification data
MS365_BASELINE=$(cat /tmp/ms365_baseline.txt 2>/dev/null | tr '\n' ',' | sed 's/,$//')
MS365_CURRENT=$(snipeit_db_query "SELECT assigned_to FROM license_seats WHERE license_id=$LIC_MS365 AND assigned_to IS NOT NULL ORDER BY assigned_to" | tr '\n' ',' | sed 's/,$//')

# Build JSON
cat <<EOF > /tmp/task_result.json
{
  "adobe_total_seats": ${ADOBE_TOTAL_SEATS:-0},
  "unauth_count": ${UNAUTH_COUNT:-0},
  "auth_users_total": ${AUTH_USERS_TOTAL:-0},
  "auth_checkout_count": ${AUTH_CHECKOUT_COUNT:-0},
  "ms365_baseline": "$MS365_BASELINE",
  "ms365_current": "$MS365_CURRENT"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="