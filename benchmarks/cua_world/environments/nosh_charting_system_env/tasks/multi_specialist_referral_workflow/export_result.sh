#!/bin/bash
# Export task results for multi_specialist_referral_workflow
# Queries MariaDB for patient Malka Hartmann (pid=12) and writes JSON result
echo "=== Exporting multi_specialist_referral_workflow results ==="

PID=12
PROVIDER_ID=2
BROOKS_ID=3

# Query encounter count
ENC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
ENC_COUNT=${ENC_COUNT:-0}

# Query TSH lab order
TSH_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_labs) LIKE '%TSH%' OR UPPER(orders_labs) LIKE '%THYROID STIMULATING%');" 2>/dev/null | tr -d '[:space:]')
TSH_COUNT=${TSH_COUNT:-0}

# Query CBC lab order
CBC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_labs) LIKE '%CBC%' OR UPPER(orders_labs) LIKE '%COMPLETE BLOOD%');" 2>/dev/null | tr -d '[:space:]')
CBC_COUNT=${CBC_COUNT:-0}

# Query endocrinology referral
ENDO_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND UPPER(orders_referrals) LIKE '%ENDO%';" 2>/dev/null | tr -d '[:space:]')
ENDO_COUNT=${ENDO_COUNT:-0}

# Query cardiology referral
CARDIO_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_referrals) LIKE '%CARDIO%' OR UPPER(orders_referrals) LIKE '%CARDIAC%');" 2>/dev/null | tr -d '[:space:]')
CARDIO_COUNT=${CARDIO_COUNT:-0}

# Query message to dr_brooks about Hartmann
MSG_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM messaging WHERE message_from=${PROVIDER_ID} AND (subject LIKE '%Hartmann%' OR subject LIKE '%Cardiology%' OR subject LIKE '%Consult%') AND (message_to=${BROOKS_ID} OR message_to='${BROOKS_ID}');" 2>/dev/null | tr -d '[:space:]')
MSG_COUNT=${MSG_COUNT:-0}

# Fallback: check any message from provider sent after setup time (regardless of to/subject)
if [ "${MSG_COUNT}" = "0" ]; then
  MSG_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
    "SELECT COUNT(*) FROM messaging WHERE message_from=${PROVIDER_ID} AND (subject LIKE '%Hartmann%' OR subject LIKE '%Cardiology%' OR (message_to=${BROOKS_ID} AND message_to IS NOT NULL));" 2>/dev/null | tr -d '[:space:]')
  MSG_COUNT=${MSG_COUNT:-0}
fi

echo "Encounter count: ${ENC_COUNT}"
echo "TSH lab orders: ${TSH_COUNT}"
echo "CBC lab orders: ${CBC_COUNT}"
echo "Endocrinology referrals: ${ENDO_COUNT}"
echo "Cardiology referrals: ${CARDIO_COUNT}"
echo "Messages to dr_brooks: ${MSG_COUNT}"

# Write JSON result
cat > /tmp/multi_specialist_referral_workflow_result.json << RESULTEOF
{
  "pid": ${PID},
  "enc_count": ${ENC_COUNT},
  "tsh_count": ${TSH_COUNT},
  "cbc_count": ${CBC_COUNT},
  "endo_referral_count": ${ENDO_COUNT},
  "cardio_referral_count": ${CARDIO_COUNT},
  "message_count": ${MSG_COUNT},
  "export_timestamp": "$(date -Iseconds)"
}
RESULTEOF

chmod 666 /tmp/multi_specialist_referral_workflow_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/multi_specialist_referral_workflow_result.json
