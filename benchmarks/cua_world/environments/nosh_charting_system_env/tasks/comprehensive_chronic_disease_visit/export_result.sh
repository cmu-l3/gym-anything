#!/bin/bash
# Export task results for comprehensive_chronic_disease_visit
# Queries MariaDB for patient Kelle Crist (pid=9) and writes JSON result
echo "=== Exporting comprehensive_chronic_disease_visit results ==="

PID=9

# Query encounter count
ENC_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM encounters WHERE pid=${PID};" 2>/dev/null | tr -d '[:space:]')
ENC_COUNT=${ENC_COUNT:-0}

# Query HbA1c lab order (stored as text in orders_labs column)
A1C_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_labs) LIKE '%A1C%' OR UPPER(orders_labs) LIKE '%HBA1C%' OR UPPER(orders_labs) LIKE '%HEMOGLOBIN A1C%' OR UPPER(orders_labs) LIKE '%GLYCOSYLATED%');" 2>/dev/null | tr -d '[:space:]')
A1C_COUNT=${A1C_COUNT:-0}

# Query CMP lab order
CMP_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND (UPPER(orders_labs) LIKE '%CMP%' OR UPPER(orders_labs) LIKE '%COMPREHENSIVE METABOLIC%' OR UPPER(orders_labs) LIKE '%METABOLIC PANEL%');" 2>/dev/null | tr -d '[:space:]')
CMP_COUNT=${CMP_COUNT:-0}

# Query endocrinology referral
ENDO_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM orders WHERE pid=${PID} AND UPPER(orders_referrals) LIKE '%ENDO%';" 2>/dev/null | tr -d '[:space:]')
ENDO_COUNT=${ENDO_COUNT:-0}

# Query Metformin active medication (rxl_date_inactive is NULL or empty or 0000-00-00)
METFORMIN_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e \
  "SELECT COUNT(*) FROM rx_list WHERE pid=${PID} AND UPPER(rxl_medication) LIKE '%METFORMIN%' AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00');" 2>/dev/null | tr -d '[:space:]')
METFORMIN_COUNT=${METFORMIN_COUNT:-0}

# Get initial baseline counts (recorded at setup time)
INIT_ENC=$(cat /tmp/ccdv_init_enc.txt 2>/dev/null | tr -d '[:space:]' || echo "0")
INIT_ORD=$(cat /tmp/ccdv_init_ord.txt 2>/dev/null | tr -d '[:space:]' || echo "0")
INIT_RX=$(cat /tmp/ccdv_init_rx.txt 2>/dev/null | tr -d '[:space:]' || echo "0")

echo "Encounter count: ${ENC_COUNT}"
echo "HbA1c lab orders: ${A1C_COUNT}"
echo "CMP lab orders: ${CMP_COUNT}"
echo "Endocrinology referrals: ${ENDO_COUNT}"
echo "Metformin active meds: ${METFORMIN_COUNT}"
echo "Initial encounter baseline: ${INIT_ENC}"

# Write JSON result
cat > /tmp/comprehensive_chronic_disease_visit_result.json << RESULTEOF
{
  "pid": ${PID},
  "enc_count": ${ENC_COUNT},
  "a1c_count": ${A1C_COUNT},
  "cmp_count": ${CMP_COUNT},
  "endo_referral_count": ${ENDO_COUNT},
  "metformin_active_count": ${METFORMIN_COUNT},
  "init_enc_baseline": ${INIT_ENC},
  "export_timestamp": "$(date -Iseconds)"
}
RESULTEOF

chmod 666 /tmp/comprehensive_chronic_disease_visit_result.json 2>/dev/null || true
echo "=== Export complete ==="
cat /tmp/comprehensive_chronic_disease_visit_result.json
