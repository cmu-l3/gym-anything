#!/bin/bash
# Export result: diabetic_care_gap_intervention
echo "=== Exporting diabetic_care_gap_intervention result ==="

TASK_NAME="diabetic_care_gap_intervention"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

INIT_IMM36=$(cat /tmp/${TASK_NAME}_init_imm36 2>/dev/null || echo "0")
INIT_IMM37=$(cat /tmp/${TASK_NAME}_init_imm37 2>/dev/null || echo "0")
INIT_IMM38=$(cat /tmp/${TASK_NAME}_init_imm38 2>/dev/null || echo "0")
INIT_ENC36=$(cat /tmp/${TASK_NAME}_init_enc36 2>/dev/null || echo "0")
INIT_ENC37=$(cat /tmp/${TASK_NAME}_init_enc37 2>/dev/null || echo "0")
INIT_ENC38=$(cat /tmp/${TASK_NAME}_init_enc38 2>/dev/null || echo "0")

# Current immunization counts
CURR_IMM36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=36;" 2>/dev/null || echo "0")
CURR_IMM37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=37;" 2>/dev/null || echo "0")
CURR_IMM38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=38;" 2>/dev/null || echo "0")

# Check for flu vaccine specifically
FLU_IMM36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=36 AND (LOWER(imm_immunization) LIKE '%influenza%' OR LOWER(imm_immunization) LIKE '%flu%' OR imm_cvx='141' OR imm_cvx='150' OR imm_cvx='88');" 2>/dev/null || echo "0")
FLU_IMM37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=37 AND (LOWER(imm_immunization) LIKE '%influenza%' OR LOWER(imm_immunization) LIKE '%flu%' OR imm_cvx='141' OR imm_cvx='150' OR imm_cvx='88');" 2>/dev/null || echo "0")
FLU_IMM38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=38 AND (LOWER(imm_immunization) LIKE '%influenza%' OR LOWER(imm_immunization) LIKE '%flu%' OR imm_cvx='141' OR imm_cvx='150' OR imm_cvx='88');" 2>/dev/null || echo "0")

IMM_NAME36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=36 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")
IMM_NAME37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=37 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")
IMM_NAME38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=38 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")

# Current encounter counts (after task start, so any new encounter counts)
CURR_ENC36=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=36;" 2>/dev/null || echo "0")
CURR_ENC37=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=37;" 2>/dev/null || echo "0")
CURR_ENC38=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=38;" 2>/dev/null || echo "0")

# Noise patients: should NOT have new flu vaccines added
NOISE_FLU39=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=39 AND (LOWER(imm_immunization) LIKE '%influenza%' OR LOWER(imm_immunization) LIKE '%flu%');" 2>/dev/null || echo "0")
NOISE_FLU40=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=40 AND (LOWER(imm_immunization) LIKE '%influenza%' OR LOWER(imm_immunization) LIKE '%flu%');" 2>/dev/null || echo "0")

cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "patients": {
        "36": {
            "name": "Sandra Pratt",
            "init_imm_count": ${INIT_IMM36},
            "curr_imm_count": ${CURR_IMM36},
            "flu_vaccine_added": $([ "${FLU_IMM36}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM36}" -gt "${INIT_IMM36}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME36 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC36},
            "curr_enc_count": ${CURR_ENC36},
            "new_encounter": $([ "${CURR_ENC36}" -gt "${INIT_ENC36}" ] && echo "true" || echo "false")
        },
        "37": {
            "name": "Gregory Holt",
            "init_imm_count": ${INIT_IMM37},
            "curr_imm_count": ${CURR_IMM37},
            "flu_vaccine_added": $([ "${FLU_IMM37}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM37}" -gt "${INIT_IMM37}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME37 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC37},
            "curr_enc_count": ${CURR_ENC37},
            "new_encounter": $([ "${CURR_ENC37}" -gt "${INIT_ENC37}" ] && echo "true" || echo "false")
        },
        "38": {
            "name": "Wendy Kaufman",
            "init_imm_count": ${INIT_IMM38},
            "curr_imm_count": ${CURR_IMM38},
            "flu_vaccine_added": $([ "${FLU_IMM38}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM38}" -gt "${INIT_IMM38}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME38 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_enc_count": ${INIT_ENC38},
            "curr_enc_count": ${CURR_ENC38},
            "new_encounter": $([ "${CURR_ENC38}" -gt "${INIT_ENC38}" ] && echo "true" || echo "false")
        }
    },
    "noise": {
        "39": {"name": "Donald Peck",  "flu_count": ${NOISE_FLU39}},
        "40": {"name": "Irene Foley",  "flu_count": ${NOISE_FLU40}}
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
