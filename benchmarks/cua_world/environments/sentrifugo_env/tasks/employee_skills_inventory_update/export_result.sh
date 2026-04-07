#!/bin/bash
echo "=== Exporting employee_skills_inventory_update results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Read table names determined during setup
ED_TABLE=$(cat /tmp/ed_table_name.txt 2>/dev/null || echo "main_empeducation")
EX_TABLE=$(cat /tmp/ex_table_name.txt 2>/dev/null || echo "main_empexperience")
SK_TABLE=$(cat /tmp/sk_table_name.txt 2>/dev/null || echo "main_empskills")

# Dump table contents to TSV files, joining with main_users to get the employeeId.
# Using TSV allows the python verifier to dynamically parse whatever columns exist.
echo "Exporting database records..."
docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e \
    "SELECT u.employeeId, e.* FROM $ED_TABLE e JOIN main_users u ON e.user_id = u.id;" > /tmp/education.tsv 2>/dev/null || echo "employeeId" > /tmp/education.tsv

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e \
    "SELECT u.employeeId, e.* FROM $EX_TABLE e JOIN main_users u ON e.user_id = u.id;" > /tmp/experience.tsv 2>/dev/null || echo "employeeId" > /tmp/experience.tsv

docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -B -e \
    "SELECT u.employeeId, e.* FROM $SK_TABLE e JOIN main_users u ON e.user_id = u.id;" > /tmp/skills.tsv 2>/dev/null || echo "employeeId" > /tmp/skills.tsv

# Record final counts
ED_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $ED_TABLE;" 2>/dev/null || echo 0)
EX_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $EX_TABLE;" 2>/dev/null || echo 0)
SK_COUNT=$(docker exec sentrifugo-db mysql -u root -prootpass123 sentrifugo -N -B -e "SELECT COUNT(*) FROM $SK_TABLE;" 2>/dev/null || echo 0)

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Combine into task result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
  "task_start": $TASK_START,
  "task_end": $TASK_END,
  "final_counts": {
    "education": ${ED_COUNT//[^0-9]/},
    "experience": ${EX_COUNT//[^0-9]/},
    "skills": ${SK_COUNT//[^0-9]/}
  }
}
EOF

# Move files to expected locations and adjust permissions
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json /tmp/education.tsv /tmp/experience.tsv /tmp/skills.tsv 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported successfully."
echo "=== Export complete ==="