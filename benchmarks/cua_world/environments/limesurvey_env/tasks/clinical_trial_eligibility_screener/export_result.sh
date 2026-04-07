#!/bin/bash
echo "=== Exporting Clinical Trial Eligibility Screener Result ==="

source /workspace/scripts/task_utils.sh

if ! type limesurvey_query &>/dev/null; then
    limesurvey_query() {
        docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e "$1" 2>/dev/null
    }
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || DISPLAY=:1 scrot "$path" 2>/dev/null || true
    }
fi

take_screenshot /tmp/task_final.png

# Find the survey
SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%cardiovascular%risk%' OR LOWER(ls.surveyls_title) LIKE '%cvr-2025%' ORDER BY s.datecreated DESC LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SID" ]; then
    SID=$(cat /tmp/cvr_survey_sid 2>/dev/null || echo "")
fi

echo "Working with SID=$SID"

SURVEY_FOUND="false"
ACTIVE="N"
ASSESSMENTS="N"
HEIGHT_MIN=""
HEIGHT_MAX=""
WEIGHT_MIN=""
WEIGHT_MAX=""
BMI_CALC_EXISTS="false"
ELIG_SCORE_EXISTS="false"
RISK_DISPLAY_EXISTS="false"
GROUPS_JSON="[]"
DIET_SUBQ_COUNT=0
DIET_ANSWER_VALUES_JSON="[]"
ASSESSMENT_RULE_COUNT=0
ASSESSMENT_RULES_JSON="[]"
QUOTA_COUNT=0
QUOTA_MEMBERS_LINKED=0
QUOTAS_LINKED_TO_SEX=0

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"

    # Survey status
    ACTIVE=$(limesurvey_query "SELECT active FROM lime_surveys WHERE sid=$SID")
    ASSESSMENTS=$(limesurvey_query "SELECT assessments FROM lime_surveys WHERE sid=$SID")

    # ===== VALIDATION ATTRIBUTES =====
    HEIGHT_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='HEIGHT_CM' AND parent_qid=0 LIMIT 1")
    if [ -n "$HEIGHT_QID" ]; then
        HEIGHT_MIN=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$HEIGHT_QID AND attribute='min_num_value_n' LIMIT 1")
        HEIGHT_MAX=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$HEIGHT_QID AND attribute='max_num_value_n' LIMIT 1")
    fi

    WEIGHT_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='WEIGHT_KG' AND parent_qid=0 LIMIT 1")
    if [ -n "$WEIGHT_QID" ]; then
        WEIGHT_MIN=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$WEIGHT_QID AND attribute='min_num_value_n' LIMIT 1")
        WEIGHT_MAX=$(limesurvey_query "SELECT value FROM lime_question_attributes WHERE qid=$WEIGHT_QID AND attribute='max_num_value_n' LIMIT 1")
    fi

    # ===== EQUATION QUESTIONS =====
    # Use docker exec to run Python INSIDE the MySQL container's network
    # But since mysql container doesn't have python, use docker exec to query and pipe through host python
    EQUATIONS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e \
        "SELECT JSON_OBJECT('title', q.title, 'formula', IFNULL(ql.question,'')) FROM lime_questions q JOIN lime_question_l10ns ql ON q.qid=ql.qid WHERE q.sid=$SID AND q.type='*' AND q.parent_qid=0 ORDER BY q.question_order" 2>/dev/null)

    BMI_CALC_FORMULA=""
    ELIG_SCORE_FORMULA=""
    RISK_DISPLAY_FORMULA=""
    if [ -n "$EQUATIONS_JSON" ]; then
        BMI_CALC_FORMULA=$(echo "$EQUATIONS_JSON" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('title') == 'BMI_CALC':
            print(obj.get('formula',''))
    except: pass
" 2>/dev/null)
        ELIG_SCORE_FORMULA=$(echo "$EQUATIONS_JSON" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('title') == 'ELIG_SCORE':
            print(obj.get('formula',''))
    except: pass
" 2>/dev/null)
        RISK_DISPLAY_FORMULA=$(echo "$EQUATIONS_JSON" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('title') == 'RISK_DISPLAY':
            print(obj.get('formula',''))
    except: pass
" 2>/dev/null)
    fi

    [ -n "$BMI_CALC_FORMULA" ] && BMI_CALC_EXISTS="true"
    [ -n "$ELIG_SCORE_FORMULA" ] && ELIG_SCORE_EXISTS="true"
    [ -n "$RISK_DISPLAY_FORMULA" ] && RISK_DISPLAY_EXISTS="true"

    # ===== GROUPS AND RELEVANCE =====
    GROUPS_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e \
        "SELECT JSON_OBJECT('gid',g.gid,'group_name',gl.group_name,'grelevance',IFNULL(g.grelevance,''),'group_order',g.group_order) FROM lime_groups g JOIN lime_group_l10ns gl ON g.gid=gl.gid WHERE g.sid=$SID ORDER BY g.group_order" 2>/dev/null \
        | python3 -c "
import sys, json
groups = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        groups.append(json.loads(line))
    except: pass
print(json.dumps(groups))
" 2>/dev/null || echo '[]')

    # ===== DIET_HABITS =====
    DIET_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='DIET_HABITS' AND parent_qid=0 LIMIT 1")
    if [ -n "$DIET_QID" ]; then
        DIET_SUBQ_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_questions WHERE parent_qid=$DIET_QID")
        DIET_SUBQ_COUNT=${DIET_SUBQ_COUNT:-0}

        DIET_ANSWER_VALUES_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e \
            "SELECT JSON_OBJECT('code',a.code,'answer',al.answer,'assessment_value',a.assessment_value,'sortorder',a.sortorder) FROM lime_answers a JOIN lime_answer_l10ns al ON a.aid=al.aid WHERE a.qid=$DIET_QID ORDER BY a.sortorder" 2>/dev/null \
            | python3 -c "
import sys, json
items = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        items.append(json.loads(line))
    except: pass
print(json.dumps(items))
" 2>/dev/null || echo '[]')
    fi

    # ===== ASSESSMENT RULES =====
    ASSESSMENT_RULES_JSON=$(docker exec limesurvey-db mysql -u limesurvey -plimesurvey_pass limesurvey -N -e \
        "SELECT JSON_OBJECT('id',id,'gid',gid,'minimum',minimum,'maximum',maximum,'message',IFNULL(message,'')) FROM lime_assessments WHERE sid=$SID ORDER BY minimum" 2>/dev/null \
        | python3 -c "
import sys, json
items = []
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        items.append(json.loads(line))
    except: pass
print(json.dumps(items))
" 2>/dev/null || echo '[]')
    ASSESSMENT_RULE_COUNT=$(echo "$ASSESSMENT_RULES_JSON" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

    # ===== QUOTAS =====
    QUOTA_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_quota WHERE sid=$SID" 2>/dev/null || echo "0")
    QUOTA_COUNT=${QUOTA_COUNT:-0}
    QUOTA_MEMBERS_LINKED=$(limesurvey_query "SELECT COUNT(DISTINCT qm.id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=$SID" 2>/dev/null || echo "0")
    QUOTA_MEMBERS_LINKED=${QUOTA_MEMBERS_LINKED:-0}

    SEX_QID=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND title='SEX' AND parent_qid=0 LIMIT 1")
    if [ -n "$SEX_QID" ]; then
        QUOTAS_LINKED_TO_SEX=$(limesurvey_query "SELECT COUNT(DISTINCT qm.quota_id) FROM lime_quota_members qm JOIN lime_quota lq ON qm.quota_id=lq.id WHERE lq.sid=$SID AND qm.qid=$SEX_QID" 2>/dev/null || echo "0")
        QUOTAS_LINKED_TO_SEX=${QUOTAS_LINKED_TO_SEX:-0}
    fi

    echo "Survey found: SID=$SID, Active=$ACTIVE, Assessments=$ASSESSMENTS"
    echo "HEIGHT validation: min=$HEIGHT_MIN, max=$HEIGHT_MAX"
    echo "WEIGHT validation: min=$WEIGHT_MIN, max=$WEIGHT_MAX"
    echo "BMI_CALC exists: $BMI_CALC_EXISTS"
    echo "ELIG_SCORE exists: $ELIG_SCORE_EXISTS"
    echo "RISK_DISPLAY exists: $RISK_DISPLAY_EXISTS"
    echo "DIET sub-questions: $DIET_SUBQ_COUNT"
    echo "Assessment rules: $ASSESSMENT_RULE_COUNT"
    echo "Quotas: $QUOTA_COUNT, linked to SEX: $QUOTAS_LINKED_TO_SEX"
fi

# Escape formulas for safe JSON inclusion
BMI_SAFE=$(echo "$BMI_CALC_FORMULA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
ELIG_SAFE=$(echo "$ELIG_SCORE_FORMULA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')
RISK_SAFE=$(echo "$RISK_DISPLAY_FORMULA" | python3 -c "import sys,json; print(json.dumps(sys.stdin.read().strip()))" 2>/dev/null || echo '""')

# Build result JSON
python3 -c "
import json

result = {
    'survey_found': $( [ \"$SURVEY_FOUND\" = \"true\" ] && echo 'True' || echo 'False' ),
    'survey_id': '$SID',
    'active': '$ACTIVE',
    'assessments_enabled': '$ASSESSMENTS',
    'validation': {
        'height_min': '$HEIGHT_MIN',
        'height_max': '$HEIGHT_MAX',
        'weight_min': '$WEIGHT_MIN',
        'weight_max': '$WEIGHT_MAX'
    },
    'equations': {
        'bmi_calc_exists': $( [ \"$BMI_CALC_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
        'bmi_calc_formula': $BMI_SAFE,
        'elig_score_exists': $( [ \"$ELIG_SCORE_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
        'elig_score_formula': $ELIG_SAFE,
        'risk_display_exists': $( [ \"$RISK_DISPLAY_EXISTS\" = \"true\" ] && echo 'True' || echo 'False' ),
        'risk_display_formula': $RISK_SAFE
    },
    'groups': $GROUPS_JSON,
    'diet_habits': {
        'subquestion_count': int('$DIET_SUBQ_COUNT' or '0'),
        'answer_values': $DIET_ANSWER_VALUES_JSON
    },
    'assessment': {
        'rule_count': int('$ASSESSMENT_RULE_COUNT' or '0'),
        'rules': $ASSESSMENT_RULES_JSON
    },
    'quotas': {
        'count': int('$QUOTA_COUNT' or '0'),
        'members_linked': int('$QUOTA_MEMBERS_LINKED' or '0'),
        'linked_to_sex': int('${QUOTAS_LINKED_TO_SEX:-0}' or '0'),
    },
    'export_timestamp': '$(date -Iseconds)'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)
print(json.dumps(result, indent=2, default=str))
" 2>/dev/null

if [ ! -f /tmp/task_result.json ]; then
    cat > /tmp/task_result.json << EOF
{
    "survey_found": $SURVEY_FOUND,
    "survey_id": "$SID",
    "active": "$ACTIVE",
    "error": "Python JSON builder failed"
}
EOF
fi

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
