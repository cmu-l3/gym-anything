#!/bin/bash
echo "=== Exporting create_interactive_case_study result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# 2. Extract Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Locate the Target Tiddler
TARGET_TITLE="Case Study: Community-Acquired Pneumonia"
TARGET_FILENAME="Case Study_ Community-Acquired Pneumonia.tid"
TIDDLER_PATH="/home/ga/mywiki/tiddlers/$TARGET_FILENAME"

# Initialize variables
TIDDLER_EXISTS="false"
CREATED_DURING_TASK="false"
FILE_SIZE_BYTES=0
TITLE_MATCH="false"
TAGS=""
BODY_TEXT=""
BODY_LENGTH=0
REVEAL_COUNT=0
BUTTON_COUNT=0
UNIQUE_STATES=0
HAS_HISTORY_CONTENT="false"
HAS_EXAM_CONTENT="false"
HAS_INV_CONTENT="false"
HAS_DX_CONTENT="false"

if [ -f "$TIDDLER_PATH" ]; then
    TIDDLER_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$TIDDLER_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TIDDLER_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi

    # Parse Title
    ACTUAL_TITLE=$(grep "^title:" "$TIDDLER_PATH" | head -1 | sed 's/^title: *//')
    if [ "$ACTUAL_TITLE" = "$TARGET_TITLE" ]; then
        TITLE_MATCH="true"
    fi

    # Parse Tags
    TAGS=$(grep "^tags:" "$TIDDLER_PATH" | head -1 | sed 's/^tags: *//')

    # Parse Body (everything after the first blank line)
    BODY_TEXT=$(awk '/^$/{found=1; next} found{print}' "$TIDDLER_PATH")
    BODY_LENGTH=${#BODY_TEXT}

    # Count Widgets
    REVEAL_COUNT=$(echo "$BODY_TEXT" | grep -o -i "<$reveal" | wc -l)
    BUTTON_COUNT=$(echo "$BODY_TEXT" | grep -o -i "<$button" | wc -l)
    
    # Extract unique state tiddlers under the required prefix
    UNIQUE_STATES=$(echo "$BODY_TEXT" | grep -o -E "\$:/state/case-pneumonia/[a-zA-Z0-9_-]+" | sort | uniq | wc -l)

    # Content Keyword Checks
    # History: "rusty sputum" AND ("pleuritic" OR "chest pain") AND "diabetes"
    if echo "$BODY_TEXT" | grep -qi "rusty sputum"; then
        if echo "$BODY_TEXT" | grep -qiE "pleuritic|chest pain"; then
            if echo "$BODY_TEXT" | grep -qi "diabetes"; then
                HAS_HISTORY_CONTENT="true"
            fi
        fi
    fi

    # Exam: "39.2" AND ("bronchial" OR "crackles") AND ("SpO2" OR "92%")
    if echo "$BODY_TEXT" | grep -q "39.2"; then
        if echo "$BODY_TEXT" | grep -qiE "bronchial|crackles"; then
            if echo "$BODY_TEXT" | grep -qiE "spo2|92%"; then
                HAS_EXAM_CONTENT="true"
            fi
        fi
    fi

    # Investigations: ("18,500" OR "18500") AND "consolidation" AND ("CRP" OR "procalcitonin")
    if echo "$BODY_TEXT" | grep -qiE "18,500|18500"; then
        if echo "$BODY_TEXT" | grep -qi "consolidation"; then
            if echo "$BODY_TEXT" | grep -qiE "crp|procalcitonin"; then
                HAS_INV_CONTENT="true"
            fi
        fi
    fi

    # Diagnosis: "CURB-65" AND ("amoxicillin" OR "antibiotic") AND "community-acquired"
    if echo "$BODY_TEXT" | grep -qi "curb-65"; then
        if echo "$BODY_TEXT" | grep -qiE "amoxicillin|antibiotic|macrolide"; then
            if echo "$BODY_TEXT" | grep -qi "community-acquired"; then
                HAS_DX_CONTENT="true"
            fi
        fi
    fi
else
    # Fallback: search for any new tiddler if the exact name is missed
    NEWEST=$(find "/home/ga/mywiki/tiddlers" -maxdepth 1 -name "*.tid" ! -name '$__*' -newer /tmp/task_start_time.txt 2>/dev/null | head -1)
    if [ -n "$NEWEST" ] && [ -f "$NEWEST" ]; then
        # Just record that *something* was created
        CREATED_DURING_TASK="true"
        ACTUAL_TITLE=$(grep "^title:" "$NEWEST" | head -1 | sed 's/^title: *//')
    fi
fi

# 4. Save Results to JSON
# Escape string function to safely dump into JSON
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//\$/\\\$}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

ESCAPED_TAGS=$(json_escape "$TAGS")
ESCAPED_TITLE=$(json_escape "$ACTUAL_TITLE")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "tiddler_exists": $TIDDLER_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "title_match": $TITLE_MATCH,
    "actual_title": "$ESCAPED_TITLE",
    "tags": "$ESCAPED_TAGS",
    "body_length": $BODY_LENGTH,
    "reveal_count": $REVEAL_COUNT,
    "button_count": $BUTTON_COUNT,
    "unique_states": $UNIQUE_STATES,
    "has_history_content": $HAS_HISTORY_CONTENT,
    "has_exam_content": $HAS_EXAM_CONTENT,
    "has_inv_content": $HAS_INV_CONTENT,
    "has_dx_content": $HAS_DX_CONTENT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

rm -f /tmp/case_study_result.json 2>/dev/null || sudo rm -f /tmp/case_study_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/case_study_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/case_study_result.json
chmod 666 /tmp/case_study_result.json 2>/dev/null || sudo chmod 666 /tmp/case_study_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/case_study_result.json"
cat /tmp/case_study_result.json
echo "=== Export complete ==="