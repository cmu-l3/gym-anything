#!/bin/bash
# Export result: care_quality_remediation
# Correct table schemas:
#   issues: issue_id, pid, issue, issue_date_active, issue_date_inactive, type, notes
#   rx_list: rxl_id, pid, rxl_medication, rxl_dosage, rxl_dosage_unit, rxl_date_inactive, ...
#   allergies: allergies_id, pid, allergies_med, allergies_reaction, allergies_severity, ...
#   encounters: eid, pid, encounter_provider, encounter_date, encounter_type, encounter_cc, ...
#   schedule: appt_id, pid, start (unix ts), end (unix ts), title, visit_type, reason, status, provider_id
echo "=== Exporting care_quality_remediation result ==="

TASK_NAME="care_quality_remediation"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Read baseline counts
INIT_ISS_41=$(cat /tmp/${TASK_NAME}_init_iss41 2>/dev/null || echo "0")
INIT_ISS_42=$(cat /tmp/${TASK_NAME}_init_iss42 2>/dev/null || echo "0")
INIT_ISS_43=$(cat /tmp/${TASK_NAME}_init_iss43 2>/dev/null || echo "0")
INIT_ISS_44=$(cat /tmp/${TASK_NAME}_init_iss44 2>/dev/null || echo "0")
INIT_ISS_45=$(cat /tmp/${TASK_NAME}_init_iss45 2>/dev/null || echo "0")
INIT_ISS_46=$(cat /tmp/${TASK_NAME}_init_iss46 2>/dev/null || echo "0")

INIT_RX_41=$(cat /tmp/${TASK_NAME}_init_rx41 2>/dev/null || echo "0")
INIT_RX_42=$(cat /tmp/${TASK_NAME}_init_rx42 2>/dev/null || echo "0")
INIT_RX_43=$(cat /tmp/${TASK_NAME}_init_rx43 2>/dev/null || echo "0")
INIT_RX_44=$(cat /tmp/${TASK_NAME}_init_rx44 2>/dev/null || echo "0")
INIT_RX_45=$(cat /tmp/${TASK_NAME}_init_rx45 2>/dev/null || echo "0")
INIT_RX_46=$(cat /tmp/${TASK_NAME}_init_rx46 2>/dev/null || echo "0")

INIT_ALL_41=$(cat /tmp/${TASK_NAME}_init_all41 2>/dev/null || echo "0")
INIT_ALL_43=$(cat /tmp/${TASK_NAME}_init_all43 2>/dev/null || echo "0")
INIT_ALL_45=$(cat /tmp/${TASK_NAME}_init_all45 2>/dev/null || echo "0")
INIT_ALL_46=$(cat /tmp/${TASK_NAME}_init_all46 2>/dev/null || echo "0")

INIT_ENC_41=$(cat /tmp/${TASK_NAME}_init_enc41 2>/dev/null || echo "0")
INIT_ENC_42=$(cat /tmp/${TASK_NAME}_init_enc42 2>/dev/null || echo "0")
INIT_ENC_43=$(cat /tmp/${TASK_NAME}_init_enc43 2>/dev/null || echo "0")
INIT_ENC_44=$(cat /tmp/${TASK_NAME}_init_enc44 2>/dev/null || echo "0")
INIT_ENC_45=$(cat /tmp/${TASK_NAME}_init_enc45 2>/dev/null || echo "0")
INIT_ENC_46=$(cat /tmp/${TASK_NAME}_init_enc46 2>/dev/null || echo "0")

INIT_SCH_41=$(cat /tmp/${TASK_NAME}_init_sch41 2>/dev/null || echo "0")
INIT_SCH_44=$(cat /tmp/${TASK_NAME}_init_sch44 2>/dev/null || echo "0")
INIT_SCH_45=$(cat /tmp/${TASK_NAME}_init_sch45 2>/dev/null || echo "0")
INIT_SCH_46=$(cat /tmp/${TASK_NAME}_init_sch46 2>/dev/null || echo "0")

# ================================================================
# PID 41: Helen Mercer
# Gaps: E11.9 problem, Sulfonamide allergy, appointment 2026-07-15, encounter
# ================================================================
CURR_ISS_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=41;" 2>/dev/null || echo "0")
ISS_E119_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=41 AND (LOWER(issue) LIKE '%e11%' OR LOWER(issue) LIKE '%diabetes%type 2%' OR LOWER(issue) LIKE '%type 2%diabetes%');" 2>/dev/null || echo "0")

CURR_ALL_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=41;" 2>/dev/null || echo "0")
ALL_SULFA_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=41 AND (LOWER(allergies_med) LIKE '%sulfonamide%' OR LOWER(allergies_med) LIKE '%sulfa%');" 2>/dev/null || echo "0")

CURR_SCH_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=41;" 2>/dev/null || echo "0")
# schedule.start is a Unix timestamp; 2026-07-15 = UNIX_TIMESTAMP('2026-07-15')
SCH_JUL15_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=41 AND start >= UNIX_TIMESTAMP('2026-07-15 00:00:00') AND start < UNIX_TIMESTAMP('2026-07-16 00:00:00');" 2>/dev/null || echo "0")

CURR_ENC_41=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=41;" 2>/dev/null || echo "0")

# ================================================================
# PID 42: Frank Costello
# Gap: Losartan dosage update to 100mg, encounter
# ================================================================
CURR_RX_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=42;" 2>/dev/null || echo "0")
LOSARTAN_DOSE_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT CONCAT(rxl_dosage, COALESCE(rxl_dosage_unit,'')) FROM rx_list WHERE pid=42 AND LOWER(rxl_medication) LIKE '%losartan%' AND rxl_date_inactive IS NULL ORDER BY rxl_id DESC LIMIT 1;" 2>/dev/null || echo "")
LOSARTAN_100_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=42 AND LOWER(rxl_medication) LIKE '%losartan%' AND rxl_date_inactive IS NULL AND rxl_dosage LIKE '%100%';" 2>/dev/null || echo "0")

CURR_ENC_42=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=42;" 2>/dev/null || echo "0")

# ================================================================
# PID 43: Beatrice Yamamoto
# Gaps: M81.0 problem, Alendronate Rx, Iodine allergy, encounter
# ================================================================
CURR_ISS_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=43;" 2>/dev/null || echo "0")
ISS_M810_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=43 AND (LOWER(issue) LIKE '%m81%' OR LOWER(issue) LIKE '%osteoporosis%');" 2>/dev/null || echo "0")

CURR_RX_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=43;" 2>/dev/null || echo "0")
RX_ALEN_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=43 AND LOWER(rxl_medication) LIKE '%alendronate%' AND rxl_date_inactive IS NULL;" 2>/dev/null || echo "0")

CURR_ALL_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=43;" 2>/dev/null || echo "0")
ALL_IODINE_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=43 AND (LOWER(allergies_med) LIKE '%iodine%' OR LOWER(allergies_med) LIKE '%contrast%');" 2>/dev/null || echo "0")

CURR_ENC_43=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=43;" 2>/dev/null || echo "0")

# ================================================================
# PID 44: Raymond Delacroix
# Gaps: K21.0 problem, Omeprazole Rx, appointment 2026-07-01, encounter
# ================================================================
CURR_ISS_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=44;" 2>/dev/null || echo "0")
ISS_K210_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=44 AND (LOWER(issue) LIKE '%k21%' OR LOWER(issue) LIKE '%gerd%' OR LOWER(issue) LIKE '%gastroesophageal%');" 2>/dev/null || echo "0")

CURR_RX_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=44;" 2>/dev/null || echo "0")
RX_OMEP_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=44 AND LOWER(rxl_medication) LIKE '%omeprazole%' AND rxl_date_inactive IS NULL;" 2>/dev/null || echo "0")

CURR_SCH_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=44;" 2>/dev/null || echo "0")
SCH_JUL01_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=44 AND start >= UNIX_TIMESTAMP('2026-07-01 00:00:00') AND start < UNIX_TIMESTAMP('2026-07-02 00:00:00');" 2>/dev/null || echo "0")

CURR_ENC_44=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=44;" 2>/dev/null || echo "0")

# ================================================================
# PID 45: Dorothy Nguyen (NOISE — should be untouched)
# ================================================================
CURR_ISS_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=45;" 2>/dev/null || echo "0")
CURR_RX_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=45;" 2>/dev/null || echo "0")
CURR_ALL_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=45;" 2>/dev/null || echo "0")
CURR_ENC_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=45;" 2>/dev/null || echo "0")
CURR_SCH_45=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=45;" 2>/dev/null || echo "0")

# ================================================================
# PID 46: Walter Fitzgerald (NOISE — should be untouched)
# ================================================================
CURR_ISS_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM issues WHERE pid=46;" 2>/dev/null || echo "0")
CURR_RX_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM rx_list WHERE pid=46;" 2>/dev/null || echo "0")
CURR_ALL_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM allergies WHERE pid=46;" 2>/dev/null || echo "0")
CURR_ENC_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM encounters WHERE pid=46;" 2>/dev/null || echo "0")
CURR_SCH_46=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -B -e "SELECT COUNT(*) FROM schedule WHERE pid=46;" 2>/dev/null || echo "0")

# ================================================================
# Write result JSON
# ================================================================
cat > /tmp/${TASK_NAME}_result.json << JSONEOF
{
    "task_start": ${TASK_START},
    "pid41_helen": {
        "name": "Helen Mercer",
        "problem_e119_found": $([ "${ISS_E119_41}" -gt "0" ] && echo "true" || echo "false"),
        "init_iss": ${INIT_ISS_41},
        "curr_iss": ${CURR_ISS_41},
        "allergy_sulfa_found": $([ "${ALL_SULFA_41}" -gt "0" ] && echo "true" || echo "false"),
        "init_all": ${INIT_ALL_41},
        "curr_all": ${CURR_ALL_41},
        "appt_jul15_found": $([ "${SCH_JUL15_41}" -gt "0" ] && echo "true" || echo "false"),
        "init_sch": ${INIT_SCH_41},
        "curr_sch": ${CURR_SCH_41},
        "init_enc": ${INIT_ENC_41},
        "curr_enc": ${CURR_ENC_41},
        "new_encounter": $([ "${CURR_ENC_41}" -gt "${INIT_ENC_41}" ] && echo "true" || echo "false")
    },
    "pid42_frank": {
        "name": "Frank Costello",
        "losartan_dose": "$(echo $LOSARTAN_DOSE_42 | tr -d '\r\n' | sed 's/"/\\"/g')",
        "losartan_100mg": $([ "${LOSARTAN_100_42}" -gt "0" ] && echo "true" || echo "false"),
        "init_rx": ${INIT_RX_42},
        "curr_rx": ${CURR_RX_42},
        "init_enc": ${INIT_ENC_42},
        "curr_enc": ${CURR_ENC_42},
        "new_encounter": $([ "${CURR_ENC_42}" -gt "${INIT_ENC_42}" ] && echo "true" || echo "false")
    },
    "pid43_beatrice": {
        "name": "Beatrice Yamamoto",
        "problem_m810_found": $([ "${ISS_M810_43}" -gt "0" ] && echo "true" || echo "false"),
        "init_iss": ${INIT_ISS_43},
        "curr_iss": ${CURR_ISS_43},
        "rx_alendronate_found": $([ "${RX_ALEN_43}" -gt "0" ] && echo "true" || echo "false"),
        "init_rx": ${INIT_RX_43},
        "curr_rx": ${CURR_RX_43},
        "allergy_iodine_found": $([ "${ALL_IODINE_43}" -gt "0" ] && echo "true" || echo "false"),
        "init_all": ${INIT_ALL_43},
        "curr_all": ${CURR_ALL_43},
        "init_enc": ${INIT_ENC_43},
        "curr_enc": ${CURR_ENC_43},
        "new_encounter": $([ "${CURR_ENC_43}" -gt "${INIT_ENC_43}" ] && echo "true" || echo "false")
    },
    "pid44_raymond": {
        "name": "Raymond Delacroix",
        "problem_k210_found": $([ "${ISS_K210_44}" -gt "0" ] && echo "true" || echo "false"),
        "init_iss": ${INIT_ISS_44},
        "curr_iss": ${CURR_ISS_44},
        "rx_omeprazole_found": $([ "${RX_OMEP_44}" -gt "0" ] && echo "true" || echo "false"),
        "init_rx": ${INIT_RX_44},
        "curr_rx": ${CURR_RX_44},
        "appt_jul01_found": $([ "${SCH_JUL01_44}" -gt "0" ] && echo "true" || echo "false"),
        "init_sch": ${INIT_SCH_44},
        "curr_sch": ${CURR_SCH_44},
        "init_enc": ${INIT_ENC_44},
        "curr_enc": ${CURR_ENC_44},
        "new_encounter": $([ "${CURR_ENC_44}" -gt "${INIT_ENC_44}" ] && echo "true" || echo "false")
    },
    "noise_pid45_dorothy": {
        "name": "Dorothy Nguyen",
        "init_iss": ${INIT_ISS_45},
        "curr_iss": ${CURR_ISS_45},
        "init_rx": ${INIT_RX_45},
        "curr_rx": ${CURR_RX_45},
        "init_all": ${INIT_ALL_45},
        "curr_all": ${CURR_ALL_45},
        "init_enc": ${INIT_ENC_45},
        "curr_enc": ${CURR_ENC_45},
        "init_sch": ${INIT_SCH_45},
        "curr_sch": ${CURR_SCH_45},
        "untouched": $([ "${CURR_ISS_45}" -eq "${INIT_ISS_45}" ] && [ "${CURR_RX_45}" -eq "${INIT_RX_45}" ] && [ "${CURR_ALL_45}" -eq "${INIT_ALL_45}" ] && [ "${CURR_ENC_45}" -eq "${INIT_ENC_45}" ] && [ "${CURR_SCH_45}" -eq "${INIT_SCH_45}" ] && echo "true" || echo "false")
    },
    "noise_pid46_walter": {
        "name": "Walter Fitzgerald",
        "init_iss": ${INIT_ISS_46},
        "curr_iss": ${CURR_ISS_46},
        "init_rx": ${INIT_RX_46},
        "curr_rx": ${CURR_RX_46},
        "init_all": ${INIT_ALL_46},
        "curr_all": ${CURR_ALL_46},
        "init_enc": ${INIT_ENC_46},
        "curr_enc": ${CURR_ENC_46},
        "init_sch": ${INIT_SCH_46},
        "curr_sch": ${CURR_SCH_46},
        "untouched": $([ "${CURR_ISS_46}" -eq "${INIT_ISS_46}" ] && [ "${CURR_RX_46}" -eq "${INIT_RX_46}" ] && [ "${CURR_ALL_46}" -eq "${INIT_ALL_46}" ] && [ "${CURR_ENC_46}" -eq "${INIT_ENC_46}" ] && [ "${CURR_SCH_46}" -eq "${INIT_SCH_46}" ] && echo "true" || echo "false")
    }
}
JSONEOF

echo "=== Export complete: ${TASK_NAME} ==="
cat /tmp/${TASK_NAME}_result.json
