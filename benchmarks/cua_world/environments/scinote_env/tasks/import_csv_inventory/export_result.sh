#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting CSV Import Inventory result ==="

# Record task end
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Load initial state
INITIAL_REPO_COUNT=$(cat /tmp/initial_repo_count.txt 2>/dev/null || echo "0")
INITIAL_ROW_COUNT=$(cat /tmp/initial_row_count.txt 2>/dev/null || echo "0")

# ============================================================
# Check 1: Inventory "Organic Solvents Collection" exists
# ============================================================
REPO_EXISTS="false"
REPO_ID=""

REPO_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repositories WHERE LOWER(name) LIKE LOWER('%organic solvents collection%');" | tr -d '[:space:]')
if [ "${REPO_COUNT:-0}" -ge 1 ]; then
    REPO_EXISTS="true"
    REPO_ID=$(scinote_db_query "SELECT id FROM repositories WHERE LOWER(name) LIKE LOWER('%organic solvents collection%') ORDER BY id DESC LIMIT 1;" | tr -d '[:space:]')
fi

# ============================================================
# Check 2 & 3: Items and Columns count
# ============================================================
ITEM_COUNT="0"
COL_COUNT="0"

if [ -n "$REPO_ID" ]; then
    ITEM_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id = ${REPO_ID};" | tr -d '[:space:]')
    COL_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_columns WHERE repository_id = ${REPO_ID};" | tr -d '[:space:]')
fi

# ============================================================
# Check 4: Spot-check specific chemical names
# ============================================================
SPOT_CHECKS_FOUND=0
CHEMICALS_FOUND=""

if [ -n "$REPO_ID" ]; then
    for chem in "Acetone" "Methanol" "Chloroform" "Toluene" "Acetonitrile"; do
        FOUND=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows WHERE repository_id = ${REPO_ID} AND LOWER(name) LIKE LOWER('%${chem}%');" | tr -d '[:space:]')
        if [ "${FOUND:-0}" -ge 1 ]; then
            SPOT_CHECKS_FOUND=$((SPOT_CHECKS_FOUND + 1))
            CHEMICALS_FOUND="${CHEMICALS_FOUND}${chem}, "
        fi
    done
fi

# ============================================================
# Check 5: Anti-gaming (New rows globally)
# ============================================================
CURRENT_ROW_COUNT=$(scinote_db_query "SELECT COUNT(*) FROM repository_rows;" | tr -d '[:space:]')
NEW_ROWS=$(( ${CURRENT_ROW_COUNT:-0} - ${INITIAL_ROW_COUNT:-0} ))

# Prepare JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": ${TASK_START},
    "task_end": ${TASK_END},
    "repo_exists": ${REPO_EXISTS},
    "repo_id": "${REPO_ID}",
    "item_count": ${ITEM_COUNT:-0},
    "col_count": ${COL_COUNT:-0},
    "spot_checks_found": ${SPOT_CHECKS_FOUND},
    "chemicals_found": "${CHEMICALS_FOUND}",
    "new_rows_detected": ${NEW_ROWS},
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="