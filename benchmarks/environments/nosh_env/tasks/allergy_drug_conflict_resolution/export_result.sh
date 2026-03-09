#!/bin/bash
# Export result: allergy_drug_conflict_resolution
echo "=== Exporting allergy_drug_conflict_resolution result ==="

TASK_NAME="allergy_drug_conflict_resolution"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

INIT_ACTIVE_RX32=$(cat /tmp/${TASK_NAME}_init_active_rx32 2>/dev/null || echo "1")
INIT_ACTIVE_RX33=$(cat /tmp/${TASK_NAME}_init_active_rx33 2>/dev/null || echo "1")
INIT_ACTIVE_RX34=$(cat /tmp/${TASK_NAME}_init_active_rx34 2>/dev/null || echo "1")
INIT_TOTAL_RX32=$(cat /tmp/${TASK_NAME}_init_total_rx32 2>/dev/null || echo "1")
INIT_TOTAL_RX33=$(cat /tmp/${TASK_NAME}_init_total_rx33 2>/dev/null || echo "1")
INIT_TOTAL_RX34=$(cat /tmp/${TASK_NAME}_init_total_rx34 2>/dev/null || echo "1")
INIT_ENC32=$(cat /tmp/${TASK_NAME}_init_enc32 2>/dev/null || echo "0")
INIT_ENC33=$(cat /tmp/${TASK_NAME}_init_enc33 2>/dev/null || echo "0")
INIT_ENC34=$(cat /tmp/${TASK_NAME}_init_enc34 2>/dev/null || echo "0")

# Current active rx counts (if decreased → conflicting med was deactivated)
CURR_ACTIVE_RX32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32 AND rxl_active='y';" 2>/dev/null || echo "0")
CURR_ACTIVE_RX33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33 AND rxl_active='y';" 2>/dev/null || echo "0")
CURR_ACTIVE_RX34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34 AND rxl_active='y';" 2>/dev/null || echo "0")

CURR_TOTAL_RX32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32;" 2>/dev/null || echo "0")
CURR_TOTAL_RX33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33;" 2>/dev/null || echo "0")
CURR_TOTAL_RX34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34;" 2>/dev/null || echo "0")

# Specifically check if conflicting drug is now inactive
TMXSMX_INACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32 AND LOWER(drug_name) LIKE '%sulfamethoxazole%' AND (rxl_active='n' OR rxl_active='0');" 2>/dev/null || echo "0")
AMOX_INACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33 AND LOWER(drug_name) LIKE '%amoxicillin%' AND (rxl_active='n' OR rxl_active='0');" 2>/dev/null || echo "0")
CODEINE_INACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34 AND LOWER(drug_name) LIKE '%codeine%' AND (rxl_active='n' OR rxl_active='0');" 2>/dev/null || echo "0")

# Also check if conflicting drug was deleted entirely (active count dropped)
TMXSMX_GONE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32 AND LOWER(drug_name) LIKE '%sulfamethoxazole%' AND rxl_active='y';" 2>/dev/null || echo "1")
AMOX_GONE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33 AND LOWER(drug_name) LIKE '%amoxicillin%' AND rxl_active='y';" 2>/dev/null || echo "1")
CODEINE_GONE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34 AND LOWER(drug_name) LIKE '%codeine%' AND rxl_active='y';" 2>/dev/null || echo "1")

# Alternative medication prescribed (any new active rx)
ALT_RX32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=32 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%sulfamethoxazole%' AND LOWER(drug_name) NOT LIKE '%trimethoprim%';" 2>/dev/null || echo "0")
ALT_RX33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=33 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%amoxicillin%' AND LOWER(drug_name) NOT LIKE '%penicillin%' AND LOWER(drug_name) NOT LIKE '%ampicillin%';" 2>/dev/null || echo "0")
ALT_RX34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=34 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%codeine%';" 2>/dev/null || echo "0")

ALT_NAME32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=32 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%sulfamethoxazole%' AND LOWER(drug_name) NOT LIKE '%trimethoprim%' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
ALT_NAME33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=33 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%amoxicillin%' AND LOWER(drug_name) NOT LIKE '%penicillin%' AND LOWER(drug_name) NOT LIKE '%ampicillin%' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
ALT_NAME34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=34 AND rxl_active='y' AND LOWER(drug_name) NOT LIKE '%codeine%' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")

# Encounter counts
CURR_ENC32=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=32;" 2>/dev/null || echo "0")
CURR_ENC33=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=33;" 2>/dev/null || echo "0")
CURR_ENC34=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=34;" 2>/dev/null || echo "0")

# Noise patient: metformin should still be active
METFORMIN_ACTIVE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=35 AND LOWER(drug_name) LIKE '%metformin%' AND rxl_active='y';" 2>/dev/null || echo "0")

cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "patients": {
        "32": {
            "name": "Marcus Odom",
            "allergy": "Sulfonamides",
            "conflict_drug": "TMP-SMX",
            "init_active_rx": ${INIT_ACTIVE_RX32},
            "curr_active_rx": ${CURR_ACTIVE_RX32},
            "init_total_rx": ${INIT_TOTAL_RX32},
            "curr_total_rx": ${CURR_TOTAL_RX32},
            "conflicting_drug_inactive": $([ "${TMXSMX_INACTIVE}" -gt "0" ] && echo "true" || echo "false"),
            "conflicting_drug_removed": $([ "${TMXSMX_GONE}" -eq "0" ] && echo "true" || echo "false"),
            "alternative_prescribed": $([ "${ALT_RX32}" -gt "0" ] && echo "true" || echo "false"),
            "alternative_drug": "$(echo $ALT_NAME32 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC32},
            "curr_enc_count": ${CURR_ENC32},
            "new_encounter": $([ "${CURR_ENC32}" -gt "${INIT_ENC32}" ] && echo "true" || echo "false")
        },
        "33": {
            "name": "Patricia Fenn",
            "allergy": "Penicillin",
            "conflict_drug": "Amoxicillin",
            "init_active_rx": ${INIT_ACTIVE_RX33},
            "curr_active_rx": ${CURR_ACTIVE_RX33},
            "init_total_rx": ${INIT_TOTAL_RX33},
            "curr_total_rx": ${CURR_TOTAL_RX33},
            "conflicting_drug_inactive": $([ "${AMOX_INACTIVE}" -gt "0" ] && echo "true" || echo "false"),
            "conflicting_drug_removed": $([ "${AMOX_GONE}" -eq "0" ] && echo "true" || echo "false"),
            "alternative_prescribed": $([ "${ALT_RX33}" -gt "0" ] && echo "true" || echo "false"),
            "alternative_drug": "$(echo $ALT_NAME33 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC33},
            "curr_enc_count": ${CURR_ENC33},
            "new_encounter": $([ "${CURR_ENC33}" -gt "${INIT_ENC33}" ] && echo "true" || echo "false")
        },
        "34": {
            "name": "Theodore Ashe",
            "allergy": "Codeine",
            "conflict_drug": "Codeine Phosphate",
            "init_active_rx": ${INIT_ACTIVE_RX34},
            "curr_active_rx": ${CURR_ACTIVE_RX34},
            "init_total_rx": ${INIT_TOTAL_RX34},
            "curr_total_rx": ${CURR_TOTAL_RX34},
            "conflicting_drug_inactive": $([ "${CODEINE_INACTIVE}" -gt "0" ] && echo "true" || echo "false"),
            "conflicting_drug_removed": $([ "${CODEINE_GONE}" -eq "0" ] && echo "true" || echo "false"),
            "alternative_prescribed": $([ "${ALT_RX34}" -gt "0" ] && echo "true" || echo "false"),
            "alternative_drug": "$(echo $ALT_NAME34 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC34},
            "curr_enc_count": ${CURR_ENC34},
            "new_encounter": $([ "${CURR_ENC34}" -gt "${INIT_ENC34}" ] && echo "true" || echo "false")
        }
    },
    "noise_pid35": {
        "name": "Nancy Briggs",
        "allergy": "Latex",
        "metformin_still_active": $([ "${METFORMIN_ACTIVE}" -gt "0" ] && echo "true" || echo "false")
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
