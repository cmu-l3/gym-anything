#!/bin/bash
echo "=== Exporting expunge_arrest_record result ==="

source /workspace/scripts/task_utils.sh

# Capture final visual state
take_screenshot /tmp/task_final.png

# Load timestamp info
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_ARREST_COUNT=$(cat /tmp/initial_arrest_count 2>/dev/null || echo "0")

# 1. Check Target Arrest Record (Should be 0)
TARGET_ARREST_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_arrests WHERE name_id IN (SELECT id FROM ncic_names WHERE name='Elias Thorne') AND arrest_reason='Criminal Trespass'")

# 2. Check Target Identity (Should be 1 - verify we didn't delete the person)
TARGET_IDENTITY_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_names WHERE name='Elias Thorne'")

# 3. Check Distractor Arrest Record (Should be 1 - verify collateral damage)
DISTRACTOR_ARREST_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_arrests WHERE name_id IN (SELECT id FROM ncic_names WHERE name='Sarah Connor')")

# 4. Check Global Counts
CURRENT_ARREST_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_arrests")

# 5. Check Modification Time (Anti-gaming approximation)
# Since MySQL 5.7 doesn't strictly track row modification times by default without schema changes,
# we rely on the count delta and current state.
# We can check if any arrests were added (which would be wrong) or if the count dropped.

RESULT_JSON=$(cat << EOF
{
    "task_start_time": $TASK_START,
    "initial_arrest_count": ${INITIAL_ARREST_COUNT:-0},
    "current_arrest_count": ${CURRENT_ARREST_COUNT:-0},
    "target_arrest_count": ${TARGET_ARREST_EXISTS:-0},
    "target_identity_count": ${TARGET_IDENTITY_EXISTS:-0},
    "distractor_arrest_count": ${DISTRACTOR_ARREST_EXISTS:-0},
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/expunge_arrest_result.json

echo "Result saved to /tmp/expunge_arrest_result.json"
cat /tmp/expunge_arrest_result.json
echo "=== Export complete ==="