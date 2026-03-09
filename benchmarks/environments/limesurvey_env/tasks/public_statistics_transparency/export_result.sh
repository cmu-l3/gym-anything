#!/bin/bash
echo "=== Exporting Public Statistics Task Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

SURVEY_ID=$(cat /tmp/task_survey_id 2>/dev/null)
if [ -z "$SURVEY_ID" ]; then
    # Fallback search
    SURVEY_ID=$(get_survey_id "Participatory Budgeting 2026")
fi

echo "Checking Survey ID: $SURVEY_ID"

# Helper for SQL queries
sql_q() {
    limesurvey_query "$1" 2>/dev/null
}

if [ -n "$SURVEY_ID" ]; then
    # 1. Check Global Survey Settings
    GLOBAL_STATS=$(sql_q "SELECT publicstatistics FROM lime_surveys WHERE sid=$SURVEY_ID")
    GLOBAL_GRAPHS=$(sql_q "SELECT publicgraphs FROM lime_surveys WHERE sid=$SURVEY_ID")
    IS_ACTIVE=$(sql_q "SELECT active FROM lime_surveys WHERE sid=$SURVEY_ID")

    echo "Global Stats: $GLOBAL_STATS"
    echo "Global Graphs: $GLOBAL_GRAPHS"
    echo "Active: $IS_ACTIVE"

    # 2. Get Question IDs
    QID_PROJ=$(sql_q "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='PROJ'")
    QID_SCORE=$(sql_q "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='SCORE'")
    QID_ZIP=$(sql_q "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='ZIP'")
    QID_INC=$(sql_q "SELECT qid FROM lime_questions WHERE sid=$SURVEY_ID AND title='INC'")

    # 3. Check Question Attributes (public_statistics, statistics_graphtype)
    # Note: If attribute is missing, it counts as 0/Off

    get_attr() {
        local qid=$1
        local attr=$2
        local val=$(sql_q "SELECT value FROM lime_question_attributes WHERE qid=$qid AND attribute='$attr'")
        echo "${val:-0}" # Default to 0 if null/empty
    }

    # PROJ (Expect: stats=1, graph=1/Pie)
    PROJ_STATS=$(get_attr "$QID_PROJ" "public_statistics")
    PROJ_GRAPH=$(get_attr "$QID_PROJ" "statistics_graphtype")

    # SCORE (Expect: stats=1)
    SCORE_STATS=$(get_attr "$QID_SCORE" "public_statistics")
    
    # ZIP (Expect: stats!=1)
    ZIP_STATS=$(get_attr "$QID_ZIP" "public_statistics")

    # INC (Expect: stats!=1)
    INC_STATS=$(get_attr "$QID_INC" "public_statistics")

    echo "PROJ: Stats=$PROJ_STATS, Graph=$PROJ_GRAPH"
    echo "SCORE: Stats=$SCORE_STATS"
    echo "ZIP: Stats=$ZIP_STATS"
    echo "INC: Stats=$INC_STATS"

    FOUND="true"
else
    FOUND="false"
fi

# Construct JSON
cat > /tmp/public_stats_result.json << EOF
{
    "survey_found": $FOUND,
    "survey_id": "$SURVEY_ID",
    "global_stats_enabled": "$GLOBAL_STATS",
    "global_graphs_enabled": "$GLOBAL_GRAPHS",
    "is_active": "$IS_ACTIVE",
    "questions": {
        "project_pref": {
            "stats_visible": "$PROJ_STATS",
            "graph_type": "$PROJ_GRAPH"
        },
        "priority_score": {
            "stats_visible": "$SCORE_STATS"
        },
        "zip_code": {
            "stats_visible": "$ZIP_STATS"
        },
        "household_income": {
            "stats_visible": "$INC_STATS"
        }
    },
    "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result JSON:"
cat /tmp/public_stats_result.json
echo "=== Export Complete ==="