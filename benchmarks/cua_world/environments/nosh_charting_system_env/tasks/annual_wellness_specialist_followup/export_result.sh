#!/bin/bash
set -e
echo "=== Exporting annual_wellness_specialist_followup results ==="

# ── Helper ────────────────────────────────────────────────────────────────────
run_sql_val() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1" 2>/dev/null | tr -d '[:space:]'
}
run_sql_raw() {
    docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "$1" 2>/dev/null
}

# ── 1. Encounter check ───────────────────────────────────────────────────────
ENC_COUNT=$(run_sql_val "SELECT COUNT(*) FROM encounters WHERE pid=900 AND encounter_DOS >= CURDATE()")

# ── 2. ROS check — query latest ROS for pid=900 created today ────────────────
ROS_RAW=$(run_sql_raw "
SELECT ros_gen, ros_eye, ros_ent, ros_cv, ros_resp, ros_gi, ros_gu, ros_mus, ros_neuro, ros_psych
FROM ros WHERE pid=900 AND ros_date >= CURDATE()
ORDER BY eid DESC LIMIT 1
")
ROS_FOUND="false"
ROS_GEN="" ; ROS_EYE="" ; ROS_ENT="" ; ROS_CV="" ; ROS_RESP=""
ROS_GI=""  ; ROS_GU=""  ; ROS_MUS="" ; ROS_NEURO="" ; ROS_PSYCH=""
if [ -n "$ROS_RAW" ]; then
    ROS_FOUND="true"
    ROS_GEN=$(echo "$ROS_RAW"   | awk -F'\t' '{print $1}')
    ROS_EYE=$(echo "$ROS_RAW"   | awk -F'\t' '{print $2}')
    ROS_ENT=$(echo "$ROS_RAW"   | awk -F'\t' '{print $3}')
    ROS_CV=$(echo "$ROS_RAW"    | awk -F'\t' '{print $4}')
    ROS_RESP=$(echo "$ROS_RAW"  | awk -F'\t' '{print $5}')
    ROS_GI=$(echo "$ROS_RAW"    | awk -F'\t' '{print $6}')
    ROS_GU=$(echo "$ROS_RAW"    | awk -F'\t' '{print $7}')
    ROS_MUS=$(echo "$ROS_RAW"   | awk -F'\t' '{print $8}')
    ROS_NEURO=$(echo "$ROS_RAW" | awk -F'\t' '{print $9}')
    ROS_PSYCH=$(echo "$ROS_RAW" | awk -F'\t' '{print $10}')
fi

# ── 3. PE check — query latest PE for pid=900 created today ──────────────────
PE_RAW=$(run_sql_raw "
SELECT pe_gen1,
       CONCAT(IFNULL(pe_eye1,''), ' ', IFNULL(pe_ent1,'')) AS heent,
       pe_cv1, pe_resp1, pe_gi1,
       IFNULL(pe, '') AS pe_catchall
FROM pe WHERE pid=900 AND pe_date >= CURDATE()
ORDER BY eid DESC LIMIT 1
")
PE_FOUND="false"
PE_GEN="" ; PE_HEENT="" ; PE_CV="" ; PE_LUNG="" ; PE_ABD="" ; PE_CATCHALL=""
if [ -n "$PE_RAW" ]; then
    PE_FOUND="true"
    PE_GEN=$(echo "$PE_RAW"      | awk -F'\t' '{print $1}')
    PE_HEENT=$(echo "$PE_RAW"    | awk -F'\t' '{print $2}')
    PE_CV=$(echo "$PE_RAW"       | awk -F'\t' '{print $3}')
    PE_LUNG=$(echo "$PE_RAW"     | awk -F'\t' '{print $4}')
    PE_ABD=$(echo "$PE_RAW"      | awk -F'\t' '{print $5}')
    PE_CATCHALL=$(echo "$PE_RAW" | awk -F'\t' '{print $6}')
fi

# ── 4. Medication checks ─────────────────────────────────────────────────────

# Metformin 500mg discontinued?
METFORMIN_500_DISCONTINUED=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%METFORMIN%'
AND CAST(rxl_dosage AS DECIMAL) < 800
AND rxl_date_inactive IS NOT NULL
AND rxl_date_inactive != ''
AND rxl_date_inactive != '0000-00-00'
")

# Metformin 1000mg active?
METFORMIN_1000_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%METFORMIN%'
AND CAST(rxl_dosage AS DECIMAL) >= 800
AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00')
")

# Clopidogrel added as active?
CLOPIDOGREL_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%CLOPIDOGREL%'
AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00')
")

# Naproxen discontinued? (NSAID-antiplatelet interaction)
NAPROXEN_DISCONTINUED=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%NAPROXEN%'
AND rxl_date_inactive IS NOT NULL
AND rxl_date_inactive != ''
AND rxl_date_inactive != '0000-00-00'
")

# Naproxen still active? (inverse check for anti-gaming analysis)
NAPROXEN_STILL_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%NAPROXEN%'
AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00')
")

# Omeprazole still active? (anti-gaming: should NOT be discontinued)
OMEPRAZOLE_STILL_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM rx_list WHERE pid=900
AND UPPER(rxl_medication) LIKE '%OMEPRAZOLE%'
AND (rxl_date_inactive IS NULL OR rxl_date_inactive = '' OR rxl_date_inactive = '0000-00-00')
")

# ── 5. Problem list checks ───────────────────────────────────────────────────

# Type 2 Diabetes present and active?
TYPE2_DIABETES_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM issues WHERE pid=900
AND (UPPER(issue) LIKE '%TYPE 2%' OR UPPER(issue) LIKE '%TYPE II%' OR UPPER(issue) LIKE '%E11%')
AND (issue_date_inactive IS NULL OR issue_date_inactive = '' OR issue_date_inactive = '0000-00-00')
")

# Type 1 Diabetes still active? (should be removed/corrected)
TYPE1_DIABETES_STILL_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM issues WHERE pid=900
AND (UPPER(issue) LIKE '%TYPE 1%' OR UPPER(issue) LIKE '%TYPE I %' OR UPPER(issue) LIKE '%E10%')
AND (issue_date_inactive IS NULL OR issue_date_inactive = '' OR issue_date_inactive = '0000-00-00')
")

# Osteoarthritis added?
OSTEOARTHRITIS_ACTIVE=$(run_sql_val "
SELECT COUNT(*) FROM issues WHERE pid=900
AND (UPPER(issue) LIKE '%OSTEOARTHRITIS%' OR UPPER(issue) LIKE '%OSTEO ARTHRITIS%' OR UPPER(issue) LIKE '%M19%')
AND (issue_date_inactive IS NULL OR issue_date_inactive = '' OR issue_date_inactive = '0000-00-00')
")

# ── 6. Lab orders ────────────────────────────────────────────────────────────
LABS_RAW=$(run_sql_raw "
SELECT UPPER(IFNULL(orders_labs,'')) FROM orders WHERE pid=900
")

HBA1C_ORDERED=0
CMP_ORDERED=0
LIPID_ORDERED=0
if [ -n "$LABS_RAW" ]; then
    HBA1C_ORDERED=$(echo "$LABS_RAW" | grep -ci 'A1C\|HBA1C\|HEMOGLOBIN A1C\|GLYCOSYLATED' || echo 0)
    CMP_ORDERED=$(echo "$LABS_RAW" | grep -ci 'CMP\|COMPREHENSIVE METABOLIC\|METABOLIC PANEL' || echo 0)
    LIPID_ORDERED=$(echo "$LABS_RAW" | grep -ci 'LIPID\|CHOLESTEROL' || echo 0)
fi

# ── 7. Ophthalmology referral ────────────────────────────────────────────────
OPHTHO_REFERRAL=$(run_sql_val "
SELECT COUNT(*) FROM orders WHERE pid=900
AND UPPER(IFNULL(orders_referrals,'')) LIKE '%OPHTHAL%'
")

# ── 8. Read baseline counts ─────────────────────────────────────────────────
INIT_ENC=$(cat /tmp/awsf_init_enc.txt 2>/dev/null || echo 0)
INIT_ROS=$(cat /tmp/awsf_init_ros.txt 2>/dev/null || echo 0)
INIT_PE=$(cat /tmp/awsf_init_pe.txt 2>/dev/null || echo 0)
INIT_ORD=$(cat /tmp/awsf_init_ord.txt 2>/dev/null || echo 0)
INIT_RX=$(cat /tmp/awsf_init_rx.txt 2>/dev/null || echo 0)
START_TIME=$(cat /tmp/awsf_start_time.txt 2>/dev/null || echo "unknown")

# ── 9. Build result JSON ─────────────────────────────────────────────────────
RESULT_FILE="/tmp/annual_wellness_specialist_followup_result.json"
TASK_END=$(date '+%Y-%m-%d %H:%M:%S')

# Convert bash booleans to Python booleans
ROS_FOUND_PY="False"
PE_FOUND_PY="False"
[ "$ROS_FOUND" = "true" ] && ROS_FOUND_PY="True"
[ "$PE_FOUND" = "true" ] && PE_FOUND_PY="True"

python3 << PYEOF
import json

data = {
    "task_start": "${START_TIME}",
    "task_end": "${TASK_END}",
    "baselines": {
        "init_enc": int("${INIT_ENC}" or "0"),
        "init_ros": int("${INIT_ROS}" or "0"),
        "init_pe":  int("${INIT_PE}" or "0"),
        "init_ord": int("${INIT_ORD}" or "0"),
        "init_rx":  int("${INIT_RX}" or "0")
    },
    "encounter": {
        "count": int("${ENC_COUNT}" or "0")
    },
    "ros": {
        "found": ${ROS_FOUND_PY},
        "gen":   """${ROS_GEN}""",
        "eye":   """${ROS_EYE}""",
        "ent":   """${ROS_ENT}""",
        "cv":    """${ROS_CV}""",
        "resp":  """${ROS_RESP}""",
        "gi":    """${ROS_GI}""",
        "gu":    """${ROS_GU}""",
        "mus":   """${ROS_MUS}""",
        "neuro": """${ROS_NEURO}""",
        "psych": """${ROS_PSYCH}"""
    },
    "pe": {
        "found":    ${PE_FOUND_PY},
        "gen":      """${PE_GEN}""",
        "heent":    """${PE_HEENT}""",
        "cv":       """${PE_CV}""",
        "lung":     """${PE_LUNG}""",
        "abd":      """${PE_ABD}""",
        "catchall": """${PE_CATCHALL}"""
    },
    "medications": {
        "metformin_500_discontinued": int("${METFORMIN_500_DISCONTINUED}" or "0"),
        "metformin_1000_active":      int("${METFORMIN_1000_ACTIVE}" or "0"),
        "clopidogrel_active":         int("${CLOPIDOGREL_ACTIVE}" or "0"),
        "naproxen_discontinued":      int("${NAPROXEN_DISCONTINUED}" or "0"),
        "naproxen_still_active":      int("${NAPROXEN_STILL_ACTIVE}" or "0"),
        "omeprazole_still_active":    int("${OMEPRAZOLE_STILL_ACTIVE}" or "0")
    },
    "problem_list": {
        "type2_diabetes_active":       int("${TYPE2_DIABETES_ACTIVE}" or "0"),
        "type1_diabetes_still_active": int("${TYPE1_DIABETES_STILL_ACTIVE}" or "0"),
        "osteoarthritis_active":       int("${OSTEOARTHRITIS_ACTIVE}" or "0")
    },
    "labs": {
        "hba1c_ordered":  int("${HBA1C_ORDERED}" or "0"),
        "cmp_ordered":    int("${CMP_ORDERED}" or "0"),
        "lipid_ordered":  int("${LIPID_ORDERED}" or "0")
    },
    "referrals": {
        "ophthalmology": int("${OPHTHO_REFERRAL}" or "0")
    }
}

with open("${RESULT_FILE}", "w") as f:
    json.dump(data, f, indent=2)

print("Result written to ${RESULT_FILE}")
PYEOF

chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "=== Export complete ==="
