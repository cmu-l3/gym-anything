#!/bin/bash
# Export result: vaccine_audit_and_schedule
echo "=== Exporting vaccine_audit_and_schedule result ==="

TASK_NAME="vaccine_audit_and_schedule"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

INIT_IMM27=$(cat /tmp/${TASK_NAME}_init_imm27 2>/dev/null || echo "0")
INIT_IMM28=$(cat /tmp/${TASK_NAME}_init_imm28 2>/dev/null || echo "0")
INIT_IMM29=$(cat /tmp/${TASK_NAME}_init_imm29 2>/dev/null || echo "0")
INIT_IMM30=$(cat /tmp/${TASK_NAME}_init_imm30 2>/dev/null || echo "0")
INIT_SCH27=$(cat /tmp/${TASK_NAME}_init_sch27 2>/dev/null || echo "0")
INIT_SCH28=$(cat /tmp/${TASK_NAME}_init_sch28 2>/dev/null || echo "0")
INIT_SCH29=$(cat /tmp/${TASK_NAME}_init_sch29 2>/dev/null || echo "0")

# Current immunization counts
CURR_IMM27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=27;" 2>/dev/null || echo "0")
CURR_IMM28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=28;" 2>/dev/null || echo "0")
CURR_IMM29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=29;" 2>/dev/null || echo "0")
CURR_IMM30=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=30;" 2>/dev/null || echo "0")

# Shingrix-specific detection (check imm_immunization or imm_cvx=187)
SHINGRIX27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=27 AND (LOWER(imm_immunization) LIKE '%shingrix%' OR LOWER(imm_immunization) LIKE '%zoster%' OR imm_cvx='187' OR imm_cvx='188');" 2>/dev/null || echo "0")
SHINGRIX28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=28 AND (LOWER(imm_immunization) LIKE '%shingrix%' OR LOWER(imm_immunization) LIKE '%zoster%' OR imm_cvx='187' OR imm_cvx='188');" 2>/dev/null || echo "0")
SHINGRIX29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=29 AND (LOWER(imm_immunization) LIKE '%shingrix%' OR LOWER(imm_immunization) LIKE '%zoster%' OR imm_cvx='187' OR imm_cvx='188');" 2>/dev/null || echo "0")
SHINGRIX30=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM immunizations WHERE pid=30 AND (LOWER(imm_immunization) LIKE '%shingrix%' OR LOWER(imm_immunization) LIKE '%zoster%' OR imm_cvx='187' OR imm_cvx='188');" 2>/dev/null || echo "0")

# Schedule counts (and check for 2026-09-15 appointments)
CURR_SCH27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=27;" 2>/dev/null || echo "0")
CURR_SCH28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=28;" 2>/dev/null || echo "0")
CURR_SCH29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=29;" 2>/dev/null || echo "0")

APT_27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=27 AND start LIKE '2026-09-15%';" 2>/dev/null || echo "0")
APT_28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=28 AND start LIKE '2026-09-15%';" 2>/dev/null || echo "0")
APT_29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=29 AND start LIKE '2026-09-15%';" 2>/dev/null || echo "0")

# Get vaccine name recorded for each patient
IMM_NAME27=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=27 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")
IMM_NAME28=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=28 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")
IMM_NAME29=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT imm_immunization FROM immunizations WHERE pid=29 ORDER BY imm_id DESC LIMIT 1;" 2>/dev/null || echo "")

cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "patients": {
        "27": {
            "name": "Virginia Slagle",
            "init_imm_count": ${INIT_IMM27},
            "curr_imm_count": ${CURR_IMM27},
            "shingrix_found": $([ "${SHINGRIX27}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM27}" -gt "${INIT_IMM27}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME27 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_sch_count": ${INIT_SCH27},
            "curr_sch_count": ${CURR_SCH27},
            "appointment_sep15": $([ "${APT_27}" -gt "0" ] && echo "true" || echo "false")
        },
        "28": {
            "name": "Harold Dunbar",
            "init_imm_count": ${INIT_IMM28},
            "curr_imm_count": ${CURR_IMM28},
            "shingrix_found": $([ "${SHINGRIX28}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM28}" -gt "${INIT_IMM28}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME28 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_sch_count": ${INIT_SCH28},
            "curr_sch_count": ${CURR_SCH28},
            "appointment_sep15": $([ "${APT_28}" -gt "0" ] && echo "true" || echo "false")
        },
        "29": {
            "name": "Agnes Morley",
            "init_imm_count": ${INIT_IMM29},
            "curr_imm_count": ${CURR_IMM29},
            "shingrix_found": $([ "${SHINGRIX29}" -gt "0" ] && echo "true" || echo "false"),
            "new_vaccine_added": $([ "${CURR_IMM29}" -gt "${INIT_IMM29}" ] && echo "true" || echo "false"),
            "latest_vaccine_name": "$(echo $IMM_NAME29 | tr -d '\r\n' | sed 's/"/\\"/g')",
            "init_sch_count": ${INIT_SCH29},
            "curr_sch_count": ${CURR_SCH29},
            "appointment_sep15": $([ "${APT_29}" -gt "0" ] && echo "true" || echo "false")
        }
    },
    "noise_pid30": {
        "name": "Clarence Webb",
        "init_imm_count": ${INIT_IMM30},
        "curr_imm_count": ${CURR_IMM30},
        "shingrix_count": ${SHINGRIX30}
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
