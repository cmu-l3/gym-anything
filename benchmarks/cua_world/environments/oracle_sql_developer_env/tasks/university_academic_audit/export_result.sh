#!/bin/bash
echo "=== Exporting University Academic Audit Results ==="

source /workspace/scripts/task_utils.sh

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /home/ga/.task_start_time 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Initialize flags
PREREQ_VW_EXISTS=false
PREREQ_FOUND_9991=false
PREREQ_FOUND_9992=false

GPA_VW_EXISTS=false
GPA_MATH_CORRECT=false

PROBATION_VW_EXISTS=false
PROBATION_FOUND_9993=false
PROBATION_FOUND_9994=false

DEPT_MV_EXISTS=false
DEPT_MV_HAS_ROWS=false

CSV_EXISTS=false
CSV_SIZE=0

# ------------------------------------------------------------------
# 1. Check PREREQ_VIOLATIONS_VW
# ------------------------------------------------------------------
PREREQ_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='REGISTRAR' AND view_name='PREREQ_VIOLATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${PREREQ_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PREREQ_VW_EXISTS=true
    
    # Check if injected violation 9991 is caught (Missing prereq entirely)
    MATCH_9991=$(oracle_query_raw "SELECT COUNT(*) FROM registrar.prereq_violations_vw WHERE student_id = 9991 AND course_id = 202;" "system" | tr -d '[:space:]')
    if [ "${MATCH_9991:-0}" -gt 0 ] 2>/dev/null; then
        PREREQ_FOUND_9991=true
    fi
    
    # Check if injected violation 9992 is caught (Took prereq but failed min grade)
    MATCH_9992=$(oracle_query_raw "SELECT COUNT(*) FROM registrar.prereq_violations_vw WHERE student_id = 9992 AND course_id = 102;" "system" | tr -d '[:space:]')
    if [ "${MATCH_9992:-0}" -gt 0 ] 2>/dev/null; then
        PREREQ_FOUND_9992=true
    fi
fi

# ------------------------------------------------------------------
# 2. Check STUDENT_TERM_GPA_VW
# ------------------------------------------------------------------
GPA_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='REGISTRAR' AND view_name='STUDENT_TERM_GPA_VW';" "system" | tr -d '[:space:]')
if [ "${GPA_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    GPA_VW_EXISTS=true
    
    # Validate exact math for Student 9995 (W grades exclusion)
    # Term 1: 101(A=4.0 * 4cr=16), 201(W=NULL). Term GPA = 16/4 = 4.0. Cum = 4.0.
    VAL_9995=$(oracle_query_raw "SELECT ROUND(term_gpa, 2) FROM registrar.student_term_gpa_vw WHERE student_id = 9995 AND term_id = 1;" "system" | tr -d '[:space:]')
    
    # Validate rolling cumulative math for Student 9993
    # Term 1: 101(D=1.0*4=4), 201(F=0*4=0) -> Term GPA = 4/8 = 0.5
    # Term 2: 101(C=2.0*4=8), 301(D=1.0*4=4) -> Term GPA = 12/8 = 1.5
    # Cum GPA after Term 2 = (4+0+8+4)/(8+8) = 16/16 = 1.0
    VAL_9993_CUM=$(oracle_query_raw "SELECT ROUND(cumulative_gpa, 2) FROM registrar.student_term_gpa_vw WHERE student_id = 9993 AND term_id = 2;" "system" | tr -d '[:space:]')
    
    if [ "${VAL_9995}" = "4" ] || [ "${VAL_9995}" = "4.0" ] || [ "${VAL_9995}" = "4.00" ]; then
        if [ "${VAL_9993_CUM}" = "1" ] || [ "${VAL_9993_CUM}" = "1.0" ] || [ "${VAL_9993_CUM}" = "1.00" ]; then
            GPA_MATH_CORRECT=true
        fi
    fi
fi

# ------------------------------------------------------------------
# 3. Check ACADEMIC_PROBATION_VW
# ------------------------------------------------------------------
PROB_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='REGISTRAR' AND view_name='ACADEMIC_PROBATION_VW';" "system" | tr -d '[:space:]')
if [ "${PROB_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROBATION_VW_EXISTS=true
    
    # Check if student 9993 is flagged for term 2
    M_9993=$(oracle_query_raw "SELECT COUNT(*) FROM registrar.academic_probation_vw WHERE student_id = 9993 AND term_id = 2;" "system" | tr -d '[:space:]')
    if [ "${M_9993:-0}" -gt 0 ] 2>/dev/null; then
        PROBATION_FOUND_9993=true
    fi
    
    # Check gap student 9994 flagged for term 3
    M_9994=$(oracle_query_raw "SELECT COUNT(*) FROM registrar.academic_probation_vw WHERE student_id = 9994 AND term_id = 3;" "system" | tr -d '[:space:]')
    if [ "${M_9994:-0}" -gt 0 ] 2>/dev/null; then
        PROBATION_FOUND_9994=true
    fi
fi

# ------------------------------------------------------------------
# 4. Check DEPARTMENT_PERFORMANCE_MV
# ------------------------------------------------------------------
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner='REGISTRAR' AND mview_name='DEPARTMENT_PERFORMANCE_MV';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    DEPT_MV_EXISTS=true
    MV_ROWS=$(oracle_query_raw "SELECT COUNT(*) FROM registrar.department_performance_mv;" "system" | tr -d '[:space:]')
    if [ "${MV_ROWS:-0}" -gt 0 ] 2>/dev/null; then
        DEPT_MV_HAS_ROWS=true
    fi
fi

# ------------------------------------------------------------------
# 5. Check CSV Export
# ------------------------------------------------------------------
CSV_PATH="/home/ga/Documents/prereq_violations.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    CSV_SIZE=$(stat -c %s "$CSV_PATH" 2>/dev/null || echo "0")
fi

# ------------------------------------------------------------------
# 6. Gather GUI Evidence
# ------------------------------------------------------------------
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "prereq_vw_exists": $PREREQ_VW_EXISTS,
    "prereq_found_9991": $PREREQ_FOUND_9991,
    "prereq_found_9992": $PREREQ_FOUND_9992,
    "gpa_vw_exists": $GPA_VW_EXISTS,
    "gpa_math_correct": $GPA_MATH_CORRECT,
    "probation_vw_exists": $PROBATION_VW_EXISTS,
    "probation_found_9993": $PROBATION_FOUND_9993,
    "probation_found_9994": $PROBATION_FOUND_9994,
    "dept_mv_exists": $DEPT_MV_EXISTS,
    "dept_mv_has_rows": $DEPT_MV_HAS_ROWS,
    "csv_exists": $CSV_EXISTS,
    "csv_size_bytes": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

# Move to final location safely
rm -f /tmp/university_audit_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/university_audit_result.json 2>/dev/null
chmod 666 /tmp/university_audit_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/university_audit_result.json"
cat /tmp/university_audit_result.json
echo "=== Export complete ==="