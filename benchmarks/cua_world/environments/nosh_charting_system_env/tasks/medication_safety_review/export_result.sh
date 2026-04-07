#!/bin/bash
# Export task results for medication_safety_review
# Queries MariaDB for patient Cordie King (pid=13) and writes JSON result
echo "=== Exporting medication_safety_review results ==="

PID=13

# Query Aspirin - is it discontinued?
# Discontinued = rxl_date_inactive is set to a real date (not NULL, '', or 0000-00-00)
ASPIRIN_DISC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%ASPIRIN%' AND rxl_date_inactive IS NOT NULL AND rxl_date_inactive != '' AND rxl_date_inactive != '0000-00-00';" 2>/dev/null | tr -d '[:space:]')
ASPIRIN_DISC=${ASPIRIN_DISC:-0}

# Query Ibuprofen - is it discontinued?
IBUPROFEN_DISC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%IBUPROFEN%' AND rxl_date_inactive IS NOT NULL AND rxl_date_inactive != '' AND rxl_date_inactive != '0000-00-00';" 2>/dev/null | tr -d '[:space:]')
IBUPROFEN_DISC=${IBUPROFEN_DISC:-0}

# Query Warfarin - is it still active (NOT discontinued)?
WARFARIN_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%WARFARIN%' AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
WARFARIN_ACTIVE=${WARFARIN_ACTIVE:-0}

# Query INR/Prothrombin Time lab order
INR_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_labs) LIKE '%INR%' OR UPPER(orders_labs) LIKE '%PROTHROMBIN%' OR UPPER(orders_labs) LIKE '%PT %' OR UPPER(orders_labs) LIKE '% PT%' OR UPPER(orders_labs) LIKE '%COAG%');" 2>/dev/null | tr -d '[:space:]')
INR_COUNT=${INR_COUNT:-0}

# Query encounter count
ENC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
ENC_COUNT=${ENC_COUNT:-0}

# Also check if Aspirin is still present as active (for do-nothing detection)
ASPIRIN_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%ASPIRIN%' AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
ASPIRIN_ACTIVE=${ASPIRIN_ACTIVE:-0}

# Check if Ibuprofen is still present as active
IBUPROFEN_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%IBUPROFEN%' AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
IBUPROFEN_ACTIVE=${IBUPROFEN_ACTIVE:-0}

echo "Aspirin discontinued: ${ASPIRIN_DISC}"
echo "Ibuprofen discontinued: ${IBUPROFEN_DISC}"
echo "Warfarin still active: ${WARFARIN_ACTIVE}"
echo "INR lab orders: ${INR_COUNT}"
echo "Encounter count: ${ENC_COUNT}"
echo "Aspirin still active (should be 0 after task): ${ASPIRIN_ACTIVE}"
echo "Ibuprofen still active (should be 0 after task): ${IBUPROFEN_ACTIVE}"

# Write JSON result
cat > /tmp/medication_safety_review_result.json << RESULTEOF
{
  "pid": ${PID},
  "aspirin_discontinued": ${ASPIRIN_DISC},
  "ibuprofen_discontinued": ${IBUPROFEN_DISC},
  "warfarin_still_active": ${WARFARIN_ACTIVE},
  "inr_lab_count": ${INR_COUNT},
  "enc_count": ${ENC_COUNT},
  "aspirin_still_active": ${ASPIRIN_ACTIVE},
  "ibuprofen_still_active": ${IBUPROFEN_ACTIVE},
  "export_timestamp": "$(date -Iseconds)"
}
RESULTEOF

chmod 666 /tmp/medication_safety_review_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/medication_safety_review_result.json
