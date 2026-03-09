#!/bin/bash
# Export result: post_visit_documentation_workflow
echo "=== Exporting post_visit_documentation_workflow result ==="

TASK_NAME="post_visit_documentation_workflow"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")
TODAY=$(date +%Y-%m-%d)

INIT_ENC=$(cat /tmp/${TASK_NAME}_init_enc 2>/dev/null || echo "0")
INIT_VIT=$(cat /tmp/${TASK_NAME}_init_vit 2>/dev/null || echo "0")
INIT_ISS=$(cat /tmp/${TASK_NAME}_init_iss 2>/dev/null || echo "0")
INIT_ALL=$(cat /tmp/${TASK_NAME}_init_all 2>/dev/null || echo "0")
INIT_RX=$(cat  /tmp/${TASK_NAME}_init_rx  2>/dev/null || echo "0")
INIT_SCH=$(cat /tmp/${TASK_NAME}_init_sch 2>/dev/null || echo "0")

# Current counts
CURR_ENC=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=31;" 2>/dev/null || echo "0")
CURR_VIT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM vitals WHERE pid=31;" 2>/dev/null || echo "0")
CURR_ISS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=31;" 2>/dev/null || echo "0")
CURR_ALL=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=31;" 2>/dev/null || echo "0")
CURR_RX=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=31;" 2>/dev/null || echo "0")
CURR_SCH=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=31;" 2>/dev/null || echo "0")

# Specific content checks

# Encounter: check for today's encounter
ENC_TODAY=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=31 AND encounter_date='${TODAY}';" 2>/dev/null || echo "0")

# Vitals: get latest vitals record (check approximate values)
# NOSH vitals table columns vary; try common column names
VITALS_ROW=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "
SELECT weight, height, pulse, temperature FROM vitals WHERE pid=31 ORDER BY vitals_id DESC LIMIT 1;
" 2>/dev/null || echo "")
VIT_WEIGHT=$(echo "$VITALS_ROW" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
VIT_HEIGHT=$(echo "$VITALS_ROW" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
VIT_PULSE=$(echo "$VITALS_ROW" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
VIT_TEMP=$(echo "$VITALS_ROW" | awk -F'\t' '{print $4}' | tr -d '[:space:]')

# BP: try bp_systolic/bp_diastolic columns, fall back to BP column
BP_SYS=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT bp_systolic FROM vitals WHERE pid=31 ORDER BY vitals_id DESC LIMIT 1;" 2>/dev/null || echo "")
BP_DIA=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT bp_diastolic FROM vitals WHERE pid=31 ORDER BY vitals_id DESC LIMIT 1;" 2>/dev/null || echo "")
if [ -z "$BP_SYS" ]; then
    # Try combined BP column
    BP_COMBINED=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT BP FROM vitals WHERE pid=31 ORDER BY vitals_id DESC LIMIT 1;" 2>/dev/null || echo "")
    BP_SYS=$(echo "$BP_COMBINED" | cut -d'/' -f1 | tr -d '[:space:]')
    BP_DIA=$(echo "$BP_COMBINED" | cut -d'/' -f2 | tr -d '[:space:]')
fi

# Problem: check for J06.9
PROBLEM_J069=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=31 AND diagnosis LIKE 'J06%';" 2>/dev/null || echo "0")
PROBLEM_NAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT diagnosis_name FROM issues WHERE pid=31 ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "")

# Allergy: check for Penicillin
ALLERGY_PENICILLIN=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=31 AND LOWER(allergen) LIKE '%penicillin%';" 2>/dev/null || echo "0")
ALLERGY_NAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT allergen FROM allergies WHERE pid=31 ORDER BY allergy_id DESC LIMIT 1;" 2>/dev/null || echo "")

# Rx: check for Azithromycin
RX_AZITHROMYCIN=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx WHERE pid=31 AND LOWER(drug_name) LIKE '%azithromycin%';" 2>/dev/null || echo "0")
RX_DOSAGE=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT rxl_dosage FROM rx WHERE pid=31 AND LOWER(drug_name) LIKE '%azithromycin%' ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
RX_NAME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT drug_name FROM rx WHERE pid=31 ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")

# Appointment: check for 2026-07-08
APT_JUL08=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=31 AND start LIKE '2026-07-08%';" 2>/dev/null || echo "0")
APT_TIME=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT start FROM schedule WHERE pid=31 ORDER BY sch_id DESC LIMIT 1;" 2>/dev/null || echo "")

cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "patient_pid": 31,
    "encounter": {
        "init_count": ${INIT_ENC},
        "curr_count": ${CURR_ENC},
        "new_encounter": $([ "${CURR_ENC}" -gt "${INIT_ENC}" ] && echo "true" || echo "false"),
        "today_encounter": $([ "${ENC_TODAY}" -gt "0" ] && echo "true" || echo "false")
    },
    "vitals": {
        "init_count": ${INIT_VIT},
        "curr_count": ${CURR_VIT},
        "new_vitals": $([ "${CURR_VIT}" -gt "${INIT_VIT}" ] && echo "true" || echo "false"),
        "weight": "$(echo $VIT_WEIGHT | tr -d '\r\n')",
        "height": "$(echo $VIT_HEIGHT | tr -d '\r\n')",
        "bp_systolic": "$(echo $BP_SYS | tr -d '\r\n')",
        "bp_diastolic": "$(echo $BP_DIA | tr -d '\r\n')",
        "pulse": "$(echo $VIT_PULSE | tr -d '\r\n')",
        "temperature": "$(echo $VIT_TEMP | tr -d '\r\n')"
    },
    "problem": {
        "init_count": ${INIT_ISS},
        "curr_count": ${CURR_ISS},
        "new_problem": $([ "${CURR_ISS}" -gt "${INIT_ISS}" ] && echo "true" || echo "false"),
        "j069_found": $([ "${PROBLEM_J069}" -gt "0" ] && echo "true" || echo "false"),
        "latest_name": "$(echo $PROBLEM_NAME | tr -d '\r\n' | sed 's/"/\\"/g')"
    },
    "allergy": {
        "init_count": ${INIT_ALL},
        "curr_count": ${CURR_ALL},
        "new_allergy": $([ "${CURR_ALL}" -gt "${INIT_ALL}" ] && echo "true" || echo "false"),
        "penicillin_found": $([ "${ALLERGY_PENICILLIN}" -gt "0" ] && echo "true" || echo "false"),
        "latest_allergen": "$(echo $ALLERGY_NAME | tr -d '\r\n' | sed 's/"/\\"/g')"
    },
    "rx": {
        "init_count": ${INIT_RX},
        "curr_count": ${CURR_RX},
        "new_rx": $([ "${CURR_RX}" -gt "${INIT_RX}" ] && echo "true" || echo "false"),
        "azithromycin_found": $([ "${RX_AZITHROMYCIN}" -gt "0" ] && echo "true" || echo "false"),
        "dosage": "$(echo $RX_DOSAGE | tr -d '\r\n' | sed 's/"/\\"/g')",
        "latest_drug": "$(echo $RX_NAME | tr -d '\r\n' | sed 's/"/\\"/g')"
    },
    "appointment": {
        "init_count": ${INIT_SCH},
        "curr_count": ${CURR_SCH},
        "new_appointment": $([ "${CURR_SCH}" -gt "${INIT_SCH}" ] && echo "true" || echo "false"),
        "jul08_found": $([ "${APT_JUL08}" -gt "0" ] && echo "true" || echo "false"),
        "latest_start": "$(echo $APT_TIME | tr -d '\r\n' | sed 's/"/\\"/g')"
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
