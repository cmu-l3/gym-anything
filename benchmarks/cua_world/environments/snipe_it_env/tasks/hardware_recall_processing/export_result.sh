#!/bin/bash
echo "=== Exporting hardware_recall_processing results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

G7_MODEL_ID=$(cat /tmp/g7_model_id.txt 2>/dev/null || echo "0")
G8_MODEL_ID=$(cat /tmp/g8_model_id.txt 2>/dev/null || echo "0")
G7_INITIAL_CHECKED_IN=$(cat /tmp/g7_initial_checked_in.txt 2>/dev/null || echo "1")

# ---------------------------------------------------------------
# 1. Check Status Label
# ---------------------------------------------------------------
RECALL_DATA=$(snipeit_db_query "SELECT id, deployable, pending, archived FROM status_labels WHERE name LIKE '%Hardware Recall%' AND deleted_at IS NULL LIMIT 1")
RECALL_ID=$(echo "$RECALL_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')

RECALL_FOUND="false"
IS_UNDEPLOYABLE="false"

if [ -n "$RECALL_ID" ]; then
    RECALL_FOUND="true"
    DEP=$(echo "$RECALL_DATA" | awk -F'\t' '{print $2}' | tr -d '[:space:]')
    PEN=$(echo "$RECALL_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
    
    # In Snipe-IT, Undeployable explicitly sets deployable=0 and pending=0
    if [ "$DEP" = "0" ] && [ "$PEN" = "0" ]; then
        IS_UNDEPLOYABLE="true"
    fi
fi

# ---------------------------------------------------------------
# 2. Check PDF Upload to G7 Model
# ---------------------------------------------------------------
MODEL_UPLOADS=$(snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE item_type LIKE '%AssetModel' AND item_id=$G7_MODEL_ID AND action_type='uploaded'" | tr -d '[:space:]')
if [ -z "$MODEL_UPLOADS" ]; then MODEL_UPLOADS=0; fi

# ---------------------------------------------------------------
# 3. Check G7 Asset Statistics
# ---------------------------------------------------------------
G7_TOTAL=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE model_id=$G7_MODEL_ID AND deleted_at IS NULL" | tr -d '[:space:]')
G7_CHECKED_IN=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE model_id=$G7_MODEL_ID AND (assigned_to IS NULL OR assigned_to=0) AND deleted_at IS NULL" | tr -d '[:space:]')

G7_QUARANTINED=0
if [ "$RECALL_FOUND" = "true" ]; then
    G7_QUARANTINED=$(snipeit_db_query "SELECT COUNT(*) FROM assets WHERE model_id=$G7_MODEL_ID AND status_id=$RECALL_ID AND deleted_at IS NULL" | tr -d '[:space:]')
fi

# ---------------------------------------------------------------
# 4. Verify G8 Assets are Unmodified
# ---------------------------------------------------------------
snipeit_db_query "SELECT id, status_id, COALESCE(assigned_to, 0) FROM assets WHERE model_id=$G8_MODEL_ID AND deleted_at IS NULL ORDER BY id" > /tmp/g8_current.txt
G8_UNMODIFIED="true"
if ! cmp -s /tmp/g8_baseline.txt /tmp/g8_current.txt; then
    G8_UNMODIFIED="false"
fi

# ---------------------------------------------------------------
# Build and Write Output JSON
# ---------------------------------------------------------------
RESULT_JSON=$(cat << JSONEOF
{
  "recall_found": $RECALL_FOUND,
  "is_undeployable": $IS_UNDEPLOYABLE,
  "model_uploads": $MODEL_UPLOADS,
  "g7_total": ${G7_TOTAL:-0},
  "initial_g7_checked_in": $G7_INITIAL_CHECKED_IN,
  "g7_checked_in": ${G7_CHECKED_IN:-0},
  "g7_quarantined": ${G7_QUARANTINED:-0},
  "g8_unmodified": $G8_UNMODIFIED
}
JSONEOF
)

safe_write_result "/tmp/hardware_recall_result.json" "$RESULT_JSON"

echo "Result saved to /tmp/hardware_recall_result.json"
cat /tmp/hardware_recall_result.json
echo "=== hardware_recall_processing export complete ==="