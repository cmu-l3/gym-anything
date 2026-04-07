#!/bin/bash
echo "=== Exporting deregister_civilian_weapon result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

# 1. Get Civilian ID
CIV_NAME="Michael DeSanta"
CIV_ID=$(opencad_db_query "SELECT id FROM ncic_names WHERE name='${CIV_NAME}' LIMIT 1")

# 2. Check Database State
# Target: DSL-882 (Should be GONE)
TARGET_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_weapons WHERE serial_number='DSL-882'")

# Safe: KEE-456 (Should be PRESENT)
SAFE_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_weapons WHERE serial_number='KEE-456'")

# Identity: Michael DeSanta (Should be PRESENT)
IDENTITY_EXISTS=$(opencad_db_query "SELECT COUNT(*) FROM ncic_names WHERE name='${CIV_NAME}'")

# Counts
INITIAL_COUNT=$(cat /tmp/initial_weapon_count 2>/dev/null || echo "0")
CURRENT_COUNT=$(opencad_db_query "SELECT COUNT(*) FROM ncic_weapons WHERE name_id=${CIV_ID:-0}")

# 3. Construct JSON
RESULT_JSON=$(cat << EOF
{
    "target_exists": ${TARGET_EXISTS:-0},
    "safe_exists": ${SAFE_EXISTS:-0},
    "identity_exists": ${IDENTITY_EXISTS:-0},
    "initial_count": ${INITIAL_COUNT:-0},
    "current_count": ${CURRENT_COUNT:-0},
    "civilian_id": "${CIV_ID}",
    "timestamp": "$(date -Iseconds)"
}
EOF
)

safe_write_result "$RESULT_JSON" /tmp/deregister_weapon_result.json

echo "Result saved to /tmp/deregister_weapon_result.json"
cat /tmp/deregister_weapon_result.json
echo "=== Export complete ==="