#!/bin/bash
# Export result: hypertension_panel_remediation
echo "=== Exporting hypertension_panel_remediation result ==="

TASK_NAME="hypertension_panel_remediation"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Baselines
INIT_RX22=$(cat /tmp/${TASK_NAME}_init_rx22 2>/dev/null || echo "0")
INIT_RX23=$(cat /tmp/${TASK_NAME}_init_rx23 2>/dev/null || echo "0")
INIT_RX24=$(cat /tmp/${TASK_NAME}_init_rx24 2>/dev/null || echo "0")
INIT_ENC22=$(cat /tmp/${TASK_NAME}_init_enc22 2>/dev/null || echo "0")
INIT_ENC23=$(cat /tmp/${TASK_NAME}_init_enc23 2>/dev/null || echo "0")
INIT_ENC24=$(cat /tmp/${TASK_NAME}_init_enc24 2>/dev/null || echo "0")

# Query current rx counts for untreated patients
CURR_RX22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=22 AND rxl_active='y';" 2>/dev/null || echo "0")
CURR_RX23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=23 AND rxl_active='y';" 2>/dev/null || echo "0")
CURR_RX24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=24 AND rxl_active='y';" 2>/dev/null || echo "0")

# Check specifically for amlodipine (case-insensitive) for each untreated patient
AMLODIPINE22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=22 AND LOWER(drug_name) LIKE '%amlodipine%' AND rxl_active='y';" 2>/dev/null || echo "0")
AMLODIPINE23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=23 AND LOWER(drug_name) LIKE '%amlodipine%' AND rxl_active='y';" 2>/dev/null || echo "0")
AMLODIPINE24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=24 AND LOWER(drug_name) LIKE '%amlodipine%' AND rxl_active='y';" 2>/dev/null || echo "0")

# Also accept any antihypertensive (in case agent chose a different first-line drug)
ANY_ANTIHTN22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=22 AND rxl_active='y' AND (LOWER(drug_name) LIKE '%amlodipine%' OR LOWER(drug_name) LIKE '%lisinopril%' OR LOWER(drug_name) LIKE '%losartan%' OR LOWER(drug_name) LIKE '%metoprolol%' OR LOWER(drug_name) LIKE '%atenolol%' OR LOWER(drug_name) LIKE '%hydrochlorothiazide%' OR LOWER(drug_name) LIKE '%valsartan%' OR LOWER(drug_name) LIKE '%ramipril%' OR LOWER(drug_name) LIKE '%enalapril%');" 2>/dev/null || echo "0")
ANY_ANTIHTN23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=23 AND rxl_active='y' AND (LOWER(drug_name) LIKE '%amlodipine%' OR LOWER(drug_name) LIKE '%lisinopril%' OR LOWER(drug_name) LIKE '%losartan%' OR LOWER(drug_name) LIKE '%metoprolol%' OR LOWER(drug_name) LIKE '%atenolol%' OR LOWER(drug_name) LIKE '%hydrochlorothiazide%' OR LOWER(drug_name) LIKE '%valsartan%' OR LOWER(drug_name) LIKE '%ramipril%' OR LOWER(drug_name) LIKE '%enalapril%');" 2>/dev/null || echo "0")
ANY_ANTIHTN24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=24 AND rxl_active='y' AND (LOWER(drug_name) LIKE '%amlodipine%' OR LOWER(drug_name) LIKE '%lisinopril%' OR LOWER(drug_name) LIKE '%losartan%' OR LOWER(drug_name) LIKE '%metoprolol%' OR LOWER(drug_name) LIKE '%atenolol%' OR LOWER(drug_name) LIKE '%hydrochlorothiazide%' OR LOWER(drug_name) LIKE '%valsartan%' OR LOWER(drug_name) LIKE '%ramipril%' OR LOWER(drug_name) LIKE '%enalapril%');" 2>/dev/null || echo "0")

# Encounter counts for untreated patients (only count encounters AFTER task start)
CURR_ENC22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=22;" 2>/dev/null || echo "0")
CURR_ENC23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=23;" 2>/dev/null || echo "0")
CURR_ENC24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=24;" 2>/dev/null || echo "0")

# Verify noise patients not over-treated (count their rx count)
RX_NOISE25=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=25 AND rxl_active='y';" 2>/dev/null || echo "1")
RX_NOISE26=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=26 AND rxl_active='y';" 2>/dev/null || echo "1")

# Capture drug names for the first antihypertensive found for each patient
DRUG22=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=22 AND rxl_active='y' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
DRUG23=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=23 AND rxl_active='y' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
DRUG24=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=24 AND rxl_active='y' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")

# Build JSON result
cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "patients": {
        "22": {
            "name": "Eleanor Whitfield",
            "init_rx_count": ${INIT_RX22},
            "curr_rx_count": ${CURR_RX22},
            "amlodipine_found": $([ "${AMLODIPINE22}" -gt "0" ] && echo "true" || echo "false"),
            "any_antihtn_found": $([ "${ANY_ANTIHTN22}" -gt "0" ] && echo "true" || echo "false"),
            "drug_name": "$(echo $DRUG22 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC22},
            "curr_enc_count": ${CURR_ENC22},
            "new_rx": $([ "${CURR_RX22}" -gt "${INIT_RX22}" ] && echo "true" || echo "false"),
            "new_encounter": $([ "${CURR_ENC22}" -gt "${INIT_ENC22}" ] && echo "true" || echo "false")
        },
        "23": {
            "name": "Russell Hartley",
            "init_rx_count": ${INIT_RX23},
            "curr_rx_count": ${CURR_RX23},
            "amlodipine_found": $([ "${AMLODIPINE23}" -gt "0" ] && echo "true" || echo "false"),
            "any_antihtn_found": $([ "${ANY_ANTIHTN23}" -gt "0" ] && echo "true" || echo "false"),
            "drug_name": "$(echo $DRUG23 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC23},
            "curr_enc_count": ${CURR_ENC23},
            "new_rx": $([ "${CURR_RX23}" -gt "${INIT_RX23}" ] && echo "true" || echo "false"),
            "new_encounter": $([ "${CURR_ENC23}" -gt "${INIT_ENC23}" ] && echo "true" || echo "false")
        },
        "24": {
            "name": "Margaret Toomey",
            "init_rx_count": ${INIT_RX24},
            "curr_rx_count": ${CURR_RX24},
            "amlodipine_found": $([ "${AMLODIPINE24}" -gt "0" ] && echo "true" || echo "false"),
            "any_antihtn_found": $([ "${ANY_ANTIHTN24}" -gt "0" ] && echo "true" || echo "false"),
            "drug_name": "$(echo $DRUG24 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC24},
            "curr_enc_count": ${CURR_ENC24},
            "new_rx": $([ "${CURR_RX24}" -gt "${INIT_RX24}" ] && echo "true" || echo "false"),
            "new_encounter": $([ "${CURR_ENC24}" -gt "${INIT_ENC24}" ] && echo "true" || echo "false")
        }
    },
    "noise": {
        "25": {"name": "Bernard Keane",  "rx_count": ${RX_NOISE25}},
        "26": {"name": "Dolores Vance",  "rx_count": ${RX_NOISE26}}
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
