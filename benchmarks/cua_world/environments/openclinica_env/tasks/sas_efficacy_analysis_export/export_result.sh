#!/bin/bash
echo "=== Exporting sas_efficacy_analysis_export result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# 1. Check if dataset exists
DATASET_EXISTS="false"
DATASET_ID=""
INCLUDED_CRFS_STR=""

DATASET_COUNT=$(oc_query "SELECT COUNT(*) FROM dataset WHERE name = 'SAS_Efficacy_Data'")
if [ "${DATASET_COUNT:-0}" -gt 0 ]; then
    DATASET_EXISTS="true"
    DATASET_ID=$(oc_query "SELECT dataset_id FROM dataset WHERE name = 'SAS_Efficacy_Data' ORDER BY dataset_id DESC LIMIT 1")
    
    # Extract the distinct CRF names that map to the items included in this dataset
    INCLUDED_CRFS=$(oc_query "
        SELECT DISTINCT c.name 
        FROM crf c 
        JOIN crf_version cv ON c.crf_id = cv.crf_id 
        JOIN item_form_metadata ifm ON cv.crf_version_id = ifm.crf_version_id 
        JOIN dataset_item_status dis ON ifm.item_id = dis.item_id 
        WHERE dis.dataset_id = $DATASET_ID
    ")
    
    # Format into a comma-separated string for JSON
    INCLUDED_CRFS_STR=$(echo "$INCLUDED_CRFS" | grep -v "^$" | tr '\n' ',' | sed 's/,$//')
fi

# 2. Check filesystem artifacts
SAS_DIR_EXISTS="false"
SAS_FILE_COUNT=0
DAT_FILE_COUNT=0

if [ -d "/home/ga/Documents/SAS_Analysis" ]; then
    SAS_DIR_EXISTS="true"
    SAS_FILE_COUNT=$(find /home/ga/Documents/SAS_Analysis -type f -name "*.sas" 2>/dev/null | wc -l)
    DAT_FILE_COUNT=$(find /home/ga/Documents/SAS_Analysis -type f \( -name "*.dat" -o -name "*.txt" \) 2>/dev/null | wc -l)
fi

# 3. Get audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")

# 4. Generate JSON export
TEMP_JSON=$(mktemp /tmp/sas_export_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dataset_exists": $DATASET_EXISTS,
    "dataset_id": "${DATASET_ID:-}",
    "included_crfs": "$(json_escape "${INCLUDED_CRFS_STR:-}")",
    "sas_dir_exists": $SAS_DIR_EXISTS,
    "sas_file_count": $SAS_FILE_COUNT,
    "dat_file_count": $DAT_FILE_COUNT,
    "audit_baseline": $AUDIT_BASELINE_COUNT,
    "audit_current": $AUDIT_LOG_COUNT,
    "result_nonce": "$(cat /tmp/result_nonce 2>/dev/null || echo "")"
}
EOF

# Move securely
rm -f /tmp/sas_export_result.json 2>/dev/null || sudo rm -f /tmp/sas_export_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/sas_export_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/sas_export_result.json
chmod 666 /tmp/sas_export_result.json 2>/dev/null || sudo chmod 666 /tmp/sas_export_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved:"
cat /tmp/sas_export_result.json

echo "=== Export complete ==="