#!/bin/bash
# Export script for Implement Tip of the Day Block task

echo "=== Exporting Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve stored IDs
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null)
COURSE_CONTEXT_ID=$(cat /tmp/course_context_id 2>/dev/null)
INITIAL_GLOSSARY_COUNT=$(cat /tmp/initial_glossary_count 2>/dev/null || echo "0")
INITIAL_BLOCK_COUNT=$(cat /tmp/initial_block_count 2>/dev/null || echo "0")

if [ -z "$COURSE_ID" ]; then
    # Fallback if setup failed or file missing
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')
fi

if [ -z "$COURSE_CONTEXT_ID" ] && [ -n "$COURSE_ID" ]; then
    COURSE_CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
fi

echo "Checking Course ID: $COURSE_ID, Context ID: $COURSE_CONTEXT_ID"

# 1. Check for Glossary
echo "Searching for Glossary 'Student Study Strategies'..."
GLOSSARY_DATA=$(moodle_query "SELECT id, name FROM mdl_glossary WHERE course=$COURSE_ID AND LOWER(name) LIKE '%student study strategies%' LIMIT 1")

GLOSSARY_FOUND="false"
GLOSSARY_ID=""
GLOSSARY_NAME=""
ENTRY_COUNT="0"
HAS_SPACED_REPETITION="false"
HAS_ACTIVE_RECALL="false"

if [ -n "$GLOSSARY_DATA" ]; then
    GLOSSARY_FOUND="true"
    GLOSSARY_ID=$(echo "$GLOSSARY_DATA" | cut -f1 | tr -d '[:space:]')
    GLOSSARY_NAME=$(echo "$GLOSSARY_DATA" | cut -f2)
    
    # Check entries
    echo "Checking entries for Glossary ID: $GLOSSARY_ID"
    ENTRY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID" | tr -d '[:space:]')
    
    # Check specific concepts (case-insensitive)
    SPACED_CHECK=$(moodle_query "SELECT id FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID AND LOWER(concept) LIKE '%spaced repetition%' LIMIT 1")
    [ -n "$SPACED_CHECK" ] && HAS_SPACED_REPETITION="true"
    
    RECALL_CHECK=$(moodle_query "SELECT id FROM mdl_glossary_entries WHERE glossaryid=$GLOSSARY_ID AND LOWER(concept) LIKE '%active recall%' LIMIT 1")
    [ -n "$RECALL_CHECK" ] && HAS_ACTIVE_RECALL="true"
else
    echo "Glossary not found."
fi

# 2. Check for Block
echo "Searching for Random Glossary Entry block..."
BLOCK_FOUND="false"
BLOCK_ID=""
BLOCK_CONFIG_BASE64=""
BLOCK_CONFIG_DECODED=""
BLOCK_TITLE=""
LINKED_GLOSSARY_ID=""

if [ -n "$COURSE_CONTEXT_ID" ]; then
    # Find the block instance in the course context
    # Note: We select the one with the highest ID assuming it's the most recently created
    BLOCK_DATA=$(moodle_query "SELECT id, configdata FROM mdl_block_instances WHERE parentcontextid=$COURSE_CONTEXT_ID AND blockname='glossary_random' ORDER BY id DESC LIMIT 1")
    
    if [ -n "$BLOCK_DATA" ]; then
        BLOCK_FOUND="true"
        BLOCK_ID=$(echo "$BLOCK_DATA" | cut -f1 | tr -d '[:space:]')
        BLOCK_CONFIG_BASE64=$(echo "$BLOCK_DATA" | cut -f2)
        
        # Decode Base64
        if [ -n "$BLOCK_CONFIG_BASE64" ]; then
            BLOCK_CONFIG_DECODED=$(echo "$BLOCK_CONFIG_BASE64" | base64 -d 2>/dev/null)
            
            # Since Moodle uses PHP serialization, we do a simple string search for the title and glossary ID
            # Serialized string looks like: ...s:5:"title";s:15:"Daily Study Tip";...s:10:"glossaryid";s:1:"5";...
            
            # Check title
            if echo "$BLOCK_CONFIG_DECODED" | grep -qi "Daily Study Tip"; then
                BLOCK_TITLE="Daily Study Tip"
            fi
            
            # Check linkage - look for the specific glossary ID we found earlier
            if [ -n "$GLOSSARY_ID" ] && echo "$BLOCK_CONFIG_DECODED" | grep -q "\"glossaryid\";s:[0-9]*:\"$GLOSSARY_ID\""; then
                LINKED_GLOSSARY_ID="$GLOSSARY_ID"
            elif [ -n "$GLOSSARY_ID" ] && echo "$BLOCK_CONFIG_DECODED" | grep -q "i:$GLOSSARY_ID;"; then
                 # Integer serialization format fallback
                 LINKED_GLOSSARY_ID="$GLOSSARY_ID"
            fi
        fi
    fi
else
    echo "Course Context ID missing."
fi

# Current counts for change detection
CURRENT_GLOSSARY_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_glossary WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_BLOCK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_block_instances WHERE parentcontextid=$COURSE_CONTEXT_ID AND blockname='glossary_random'" | tr -d '[:space:]')

# Create JSON result
TEMP_JSON=$(mktemp /tmp/tip_block_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_glossary_count": ${INITIAL_GLOSSARY_COUNT:-0},
    "current_glossary_count": ${CURRENT_GLOSSARY_COUNT:-0},
    "glossary_found": $GLOSSARY_FOUND,
    "glossary_id": "${GLOSSARY_ID}",
    "glossary_name": "${GLOSSARY_NAME}",
    "entry_count": ${ENTRY_COUNT:-0},
    "has_spaced_repetition": $HAS_SPACED_REPETITION,
    "has_active_recall": $HAS_ACTIVE_RECALL,
    "initial_block_count": ${INITIAL_BLOCK_COUNT:-0},
    "current_block_count": ${CURRENT_BLOCK_COUNT:-0},
    "block_found": $BLOCK_FOUND,
    "block_title_match": $([ "$BLOCK_TITLE" == "Daily Study Tip" ] && echo "true" || echo "false"),
    "block_linked_glossary_match": $([ "$LINKED_GLOSSARY_ID" == "$GLOSSARY_ID" ] && [ -n "$GLOSSARY_ID" ] && echo "true" || echo "false"),
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/implement_tip_of_the_day_block_result.json

echo ""
cat /tmp/implement_tip_of_the_day_block_result.json
echo ""
echo "=== Export Complete ==="