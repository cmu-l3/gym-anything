#!/bin/bash
echo "=== Exporting interim_data_extract result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

DM_STUDY_ID=$(oc_query "SELECT study_id FROM study WHERE unique_identifier = 'DM-TRIAL-2024' AND status_id != 3 LIMIT 1")

# 1. Check for the Dataset Definition
DATASET_DATA=$(oc_query "SELECT dataset_id, name, description FROM dataset WHERE study_id = $DM_STUDY_ID AND LOWER(name) LIKE '%dm2024%interim%vitals%' AND status_id != 5 ORDER BY dataset_id DESC LIMIT 1")

DATASET_EXISTS="false"
DATASET_ID="0"
DATASET_NAME=""
DATASET_ITEMS_MAPPED="false"

if [ -n "$DATASET_DATA" ]; then
    DATASET_EXISTS="true"
    DATASET_ID=$(echo "$DATASET_DATA" | cut -d'|' -f1)
    DATASET_NAME=$(echo "$DATASET_DATA" | cut -d'|' -f2)
    
    # Check if items are actually mapped to this dataset
    ITEM_COUNT=$(oc_query "SELECT COUNT(*) FROM dataset_item_status WHERE dataset_id = $DATASET_ID")
    if [ "${ITEM_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        DATASET_ITEMS_MAPPED="true"
    fi
fi
echo "Dataset Exists: $DATASET_EXISTS (ID: $DATASET_ID, Name: $DATASET_NAME, Items Mapped: $DATASET_ITEMS_MAPPED)"

# 2. Check for Export Jobs in DB (archived_dataset_file)
EXPORT_JOB_EXISTS="false"
if [ "$DATASET_ID" != "0" ]; then
    JOB_COUNT=$(oc_query "SELECT COUNT(*) FROM archived_dataset_file WHERE dataset_id = $DATASET_ID")
    if [ "${JOB_COUNT:-0}" -gt 0 ] 2>/dev/null; then
        EXPORT_JOB_EXISTS="true"
    fi
fi
echo "DB Export Job Exists: $EXPORT_JOB_EXISTS"

# 3. Check for Generated Files on Filesystem
# 3a. Check User Downloads folder
LOCAL_EXPORT_FOUND="false"
LOCAL_EXPORT_PATH=""
LOCAL_FILE=$(find /home/ga/Downloads /home/ga/Desktop -type f -newer /tmp/task_start_time.txt \( -name "*.txt" -o -name "*.csv" -o -name "*.tsv" -o -name "*.zip" \) 2>/dev/null | head -1)

if [ -n "$LOCAL_FILE" ]; then
    LOCAL_EXPORT_FOUND="true"
    LOCAL_EXPORT_PATH="$LOCAL_FILE"
fi

# 3b. Check Container Tomcat Data Dir
CONTAINER_EXPORT_FOUND="false"
CONTAINER_EXPORT_PATH=""
CONTAINER_FILE=$(docker exec oc-app find /usr/local/tomcat/openclinica.data/datasets/ -type f -mmin -60 \( -name "*.txt" -o -name "*.csv" -o -name "*.tsv" -o -name "*.zip" \) 2>/dev/null | head -1)

if [ -n "$CONTAINER_FILE" ]; then
    CONTAINER_EXPORT_FOUND="true"
    CONTAINER_EXPORT_PATH="$CONTAINER_FILE"
fi

echo "Local Export Found: $LOCAL_EXPORT_FOUND ($LOCAL_EXPORT_PATH)"
echo "Container Export Found: $CONTAINER_EXPORT_FOUND ($CONTAINER_EXPORT_PATH)"

# 4. Anti-gaming checks
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

TEMP_JSON=$(mktemp /tmp/interim_data_extract_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dataset_exists": $DATASET_EXISTS,
    "dataset_id": $DATASET_ID,
    "dataset_name": "$(json_escape "${DATASET_NAME:-}")",
    "dataset_items_mapped": $DATASET_ITEMS_MAPPED,
    "export_job_exists": $EXPORT_JOB_EXISTS,
    "local_export_found": $LOCAL_EXPORT_FOUND,
    "local_export_path": "$(json_escape "${LOCAL_EXPORT_PATH:-}")",
    "container_export_found": $CONTAINER_EXPORT_FOUND,
    "container_export_path": "$(json_escape "${CONTAINER_EXPORT_PATH:-}")",
    "audit_baseline": $AUDIT_BASELINE_COUNT,
    "audit_current": $AUDIT_LOG_COUNT,
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo '')"
}
EOF

# Ensure clean move/permissions
rm -f /tmp/interim_data_extract_result.json 2>/dev/null || sudo rm -f /tmp/interim_data_extract_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/interim_data_extract_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/interim_data_extract_result.json
chmod 666 /tmp/interim_data_extract_result.json 2>/dev/null || sudo chmod 666 /tmp/interim_data_extract_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="