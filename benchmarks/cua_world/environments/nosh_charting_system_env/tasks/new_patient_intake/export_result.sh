#!/bin/bash
# Export task results for new_patient_intake
# Queries MariaDB for patient Hobert Wuckert (pid=11) and writes JSON result
echo "=== Exporting new_patient_intake results ==="

PID=11

# Query other_history count (social + family history entries)
HISTORY_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM other_history WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
HISTORY_COUNT=${HISTORY_COUNT:-0}

# Query insurance count
INSURANCE_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM insurance WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
INSURANCE_COUNT=${INSURANCE_COUNT:-0}

# Query encounter count
ENC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
ENC_COUNT=${ENC_COUNT:-0}

# Try to get insurance name/type from first insurance record (for partial content verification)
INSURANCE_NAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COALESCE(insurance_plan_name, insurance_company_name, insurance_name, '') FROM insurance WHERE pid=${PID} LIMIT 1;" 2>/dev/null | tr -d '[:space:]' | head -c 100 || echo "")
# Fallback: try generic text columns if specific ones don't exist
if [ -z "$INSURANCE_NAME" ]; then
  INSURANCE_NAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT GROUP_CONCAT(COLUMN_NAME) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA='nosh' AND TABLE_NAME='insurance';" 2>/dev/null || echo "unknown_schema")
fi

echo "History count (other_history): ${HISTORY_COUNT}"
echo "Insurance count: ${INSURANCE_COUNT}"
echo "Encounter count: ${ENC_COUNT}"

# Write JSON result
cat > /tmp/new_patient_intake_result.json << RESULTEOF
{
  "pid": ${PID},
  "history_count": ${HISTORY_COUNT},
  "insurance_count": ${INSURANCE_COUNT},
  "enc_count": ${ENC_COUNT},
  "export_timestamp": "$(date -Iseconds)"
}
RESULTEOF

chmod 666 /tmp/new_patient_intake_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/new_patient_intake_result.json
