#!/bin/bash
# Export task results for posthospitalization_med_reconciliation
# Queries MariaDB for patient Sherill Botsford (pid=10) and writes JSON result
echo "=== Exporting posthospitalization_med_reconciliation results ==="

PID=10

# Query Lisinopril 5mg - is it discontinued?
# Discontinued = rxl_date_inactive is set to a real date (not NULL, '', or 0000-00-00)
LIS5_DISC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%LISINOPRIL%' AND CAST(rxl_dosage AS DECIMAL) < 8 AND rxl_date_inactive IS NOT NULL AND rxl_date_inactive != '' AND rxl_date_inactive != '0000-00-00';" 2>/dev/null | tr -d '[:space:]')
LIS5_DISC=${LIS5_DISC:-0}

# Query Amlodipine 5mg - is it discontinued?
AML5_DISC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%AMLODIPINE%' AND CAST(rxl_dosage AS DECIMAL) < 8 AND rxl_date_inactive IS NOT NULL AND rxl_date_inactive != '' AND rxl_date_inactive != '0000-00-00';" 2>/dev/null | tr -d '[:space:]')
AML5_DISC=${AML5_DISC:-0}

# Query Lisinopril 10mg - is it active?
LIS10_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%LISINOPRIL%' AND CAST(rxl_dosage AS DECIMAL) >= 8 AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
LIS10_ACTIVE=${LIS10_ACTIVE:-0}

# Query Amlodipine 10mg - is it active?
AML10_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%AMLODIPINE%' AND CAST(rxl_dosage AS DECIMAL) >= 8 AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
AML10_ACTIVE=${AML10_ACTIVE:-0}

# Query encounter count
ENC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
ENC_COUNT=${ENC_COUNT:-0}

INIT_ENC=$(cat /tmp/phmr_init_enc.txt 2>/dev/null | tr -d '[:space:]' || echo "0")

echo "Lisinopril 5mg discontinued: ${LIS5_DISC}"
echo "Amlodipine 5mg discontinued: ${AML5_DISC}"
echo "Lisinopril 10mg active: ${LIS10_ACTIVE}"
echo "Amlodipine 10mg active: ${AML10_ACTIVE}"
echo "Encounter count: ${ENC_COUNT}"

# Write JSON result
cat > /tmp/posthospitalization_med_reconciliation_result.json << RESULTEOF
{
  "pid": ${PID},
  "lisinopril_5mg_discontinued": ${LIS5_DISC},
  "amlodipine_5mg_discontinued": ${AML5_DISC},
  "lisinopril_10mg_active": ${LIS10_ACTIVE},
  "amlodipine_10mg_active": ${AML10_ACTIVE},
  "enc_count": ${ENC_COUNT},
  "init_enc_baseline": ${INIT_ENC},
  "export_timestamp": "$(date -Iseconds)"
}
RESULTEOF

chmod 666 /tmp/posthospitalization_med_reconciliation_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/posthospitalization_med_reconciliation_result.json
