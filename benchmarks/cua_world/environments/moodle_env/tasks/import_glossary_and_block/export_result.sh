#!/bin/bash
echo "=== Exporting Import Glossary and Block task results ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png ga

# 2. Query Database for Verification Data
COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='MED101'" | head -n 1)

GLOSSARY_EXISTS="false"
GLOSSARY_ID=""
ENTRY_COUNT=0
BLOCK_EXISTS="false"

if [ -n "$COURSE_ID" ]; then
    # Check for glossary "Core Medical Terms"
    GLOSSARY_DATA=$(moodle_query "SELECT id, timecreated FROM mdl_glossary WHERE course=$COURSE_ID AND LOWER(TRIM(name))='core medical terms' ORDER BY id DESC LIMIT 1")
    
    if [ -n "$GLOSSARY_DATA" ]; then
        GLOSSARY_EXISTS="true"
        GLOSSARY_ID=$(echo "$GLOSSARY_DATA" | cut -f1)
        GLOSSARY_TIMECREATED=$(echo "$GLOSSARY_DATA" | cut -f2)
        
        # Count entries in this glossary
        ENTRY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID")
    fi
    
    # Check for the "Random glossary entry" block associated with the course
    # Moodle course context level is 50
    CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | head -n 1)
    
    if [ -n "$CONTEXT_ID" ]; then
        BLOCK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_block_instances WHERE parentcontextid=$CONTEXT_ID AND blockname='random_glossary_ent'")
        if [ "$BLOCK_COUNT" -gt 0 ]; then
            BLOCK_EXISTS="true"
        fi
    fi
fi

# 3. Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "course_id": "${COURSE_ID:-0}",
    "glossary_exists": $GLOSSARY_EXISTS,
    "glossary_id": "${GLOSSARY_ID:-0}",
    "entry_count": ${ENTRY_COUNT:-0},
    "block_exists": $BLOCK_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Handle permissions safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="