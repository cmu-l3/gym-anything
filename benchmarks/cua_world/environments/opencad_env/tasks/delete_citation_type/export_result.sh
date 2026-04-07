#!/bin/bash
echo "=== Exporting delete_citation_type result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Database State
TARGET_TYPE="Unsecured Excavation"

# Check if the target record still exists
TARGET_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM citation_types WHERE citation_type='$TARGET_TYPE'")

# Get current total count
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM citation_types")

# Get initial count from setup
INITIAL_COUNT=$(cat /tmp/initial_citation_count 2>/dev/null || echo "0")

# Check if other records still exist (Anti-gaming: did they wipe the table?)
# We expect at least the distractors we added in setup to remain
OTHERS_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM citation_types WHERE citation_type IN ('Speeding', 'Parking Violation', 'Reckless Driving')")

# 3. Construct JSON Result
# We use python to ensure safe JSON construction
RESULT_JSON=$(python3 -c "import json
print(json.dumps({
    'target_exists': $TARGET_EXISTS > 0,
    'initial_count': int('$INITIAL_COUNT'),
    'current_count': int('$CURRENT_COUNT'),
    'others_count': int('$OTHERS_COUNT'),
    'timestamp': '$(date -Iseconds)'
}))")

# 4. Save result
safe_write_result "$RESULT_JSON" /tmp/delete_citation_type_result.json

echo "Result saved to /tmp/delete_citation_type_result.json"
cat /tmp/delete_citation_type_result.json
echo "=== Export complete ==="