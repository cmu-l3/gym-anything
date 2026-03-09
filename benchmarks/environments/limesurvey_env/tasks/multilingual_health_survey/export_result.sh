#!/bin/bash
echo "=== Exporting Multilingual Health Survey Result ==="

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

take_screenshot /tmp/task_end_screenshot.png

SID=$(limesurvey_query "SELECT s.sid FROM lime_surveys s JOIN lime_surveys_languagesettings ls ON s.sid=ls.surveyls_survey_id WHERE LOWER(ls.surveyls_title) LIKE '%vaccine%hesitancy%' OR LOWER(ls.surveyls_title) LIKE '%vaccine%acceptance%' LIMIT 1" 2>/dev/null || echo "")
if [ -z "$SID" ]; then
    SID=$(cat /tmp/multilingual_survey_sid 2>/dev/null || echo "")
fi

echo "Working with SID=$SID"

SURVEY_FOUND="false"
SPANISH_ADDED="false"
SPANISH_TITLE=""
SPANISH_TITLE_HAS_VACUN="false"
SPANISH_QUESTION_COUNT=0
SPANISH_ANSWER_COUNT=0
GROUP_TRANSLATION_COUNT=0
TOTAL_LANGUAGES=0
ENGLISH_PRESENT="false"

if [ -n "$SID" ]; then
    SURVEY_FOUND="true"

    # Check which languages are configured
    TOTAL_LANGUAGES=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID" 2>/dev/null || echo "0")
    TOTAL_LANGUAGES=${TOTAL_LANGUAGES:-0}

    ENGLISH_PRESENT_CHECK=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='en'" 2>/dev/null || echo "0")
    [ "${ENGLISH_PRESENT_CHECK:-0}" -gt 0 ] && ENGLISH_PRESENT="true"

    # Check if Spanish (es) was added as a survey language
    SPANISH_CHECK=$(limesurvey_query "SELECT COUNT(*) FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='es'" 2>/dev/null || echo "0")
    if [ "${SPANISH_CHECK:-0}" -gt 0 ]; then
        SPANISH_ADDED="true"
        SPANISH_TITLE=$(limesurvey_query "SELECT surveyls_title FROM lime_surveys_languagesettings WHERE surveyls_survey_id=$SID AND surveyls_language='es'" 2>/dev/null || echo "")
        if echo "$SPANISH_TITLE" | grep -qi "vacun\|encuesta\|aceptaci\|hesitaci\|vacuna"; then
            SPANISH_TITLE_HAS_VACUN="true"
        fi
    fi

    # Check Spanish question translations (lime_question_l10ns for 'es')
    # Get all question IDs for this survey
    SURVEY_QIDS=$(limesurvey_query "SELECT qid FROM lime_questions WHERE sid=$SID AND parent_qid=0" 2>/dev/null || echo "")

    if [ -n "$SURVEY_QIDS" ]; then
        SPANISH_QUESTION_COUNT=$(limesurvey_query "SELECT COUNT(DISTINCT ql.qid) FROM lime_question_l10ns ql JOIN lime_questions q ON ql.qid=q.qid WHERE q.sid=$SID AND q.parent_qid=0 AND ql.language='es' AND ql.question IS NOT NULL AND ql.question != ''" 2>/dev/null || echo "0")
        SPANISH_QUESTION_COUNT=${SPANISH_QUESTION_COUNT:-0}
    fi

    # Check Spanish answer translations
    SPANISH_ANSWER_COUNT=$(limesurvey_query "SELECT COUNT(DISTINCT al.aid) FROM lime_answer_l10ns al JOIN lime_answers a ON al.aid=a.id JOIN lime_questions q ON a.qid=q.qid WHERE q.sid=$SID AND al.language='es' AND al.answer IS NOT NULL AND al.answer != ''" 2>/dev/null || echo "0")
    SPANISH_ANSWER_COUNT=${SPANISH_ANSWER_COUNT:-0}

    # Check group translations
    GROUP_TRANSLATION_COUNT=$(limesurvey_query "SELECT COUNT(*) FROM lime_group_l10ns gl JOIN lime_groups g ON gl.gid=g.gid WHERE g.sid=$SID AND gl.language='es' AND gl.group_name IS NOT NULL AND gl.group_name != ''" 2>/dev/null || echo "0")
    GROUP_TRANSLATION_COUNT=${GROUP_TRANSLATION_COUNT:-0}

    echo "Languages: $TOTAL_LANGUAGES, Spanish added: $SPANISH_ADDED"
    echo "Spanish title: $SPANISH_TITLE"
    echo "Spanish questions: $SPANISH_QUESTION_COUNT, Spanish answers: $SPANISH_ANSWER_COUNT"
    echo "Spanish group translations: $GROUP_TRANSLATION_COUNT"
fi

SPANISH_TITLE_SAFE=$(echo "$SPANISH_TITLE" | sed 's/"/\\"/g' | tr -d '\n\r' | head -c 200)

cat > /tmp/multilingual_result.json << EOF
{
    "survey_id": "$SID",
    "survey_found": $SURVEY_FOUND,
    "total_languages": $TOTAL_LANGUAGES,
    "english_present": $ENGLISH_PRESENT,
    "spanish_added": $SPANISH_ADDED,
    "spanish_survey_title": "$SPANISH_TITLE_SAFE",
    "spanish_title_has_vaccine_keyword": $SPANISH_TITLE_HAS_VACUN,
    "spanish_question_translations": $SPANISH_QUESTION_COUNT,
    "spanish_answer_translations": $SPANISH_ANSWER_COUNT,
    "spanish_group_translations": $GROUP_TRANSLATION_COUNT,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo ""
cat /tmp/multilingual_result.json
echo ""
echo "=== Export Complete ==="
