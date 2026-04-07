#!/bin/bash
# Export results for Short-Term Rental Ordinance Enforcement task
echo "=== Exporting STR Ordinance Enforcement results ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# Initialize all flags
VW_CLEANED_EXISTS=false
MV_VIOLATIONS_EXISTS=false
EXTRACTED_COUNT=0
UNLICENSED_DETECTED=0
EXPIRED_DETECTED=0
DUPLICATE_DETECTED=0
COMMERCIAL_DETECTED=0
OVER_LIMIT_DETECTED=0
CSV_EXISTS=false
CSV_SIZE=0

# --- Check VW_CLEANED_LISTINGS ---
VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'HOUSING_ADMIN' AND view_name = 'VW_CLEANED_LISTINGS';" "system" | tr -d '[:space:]')
if [ "${VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    VW_CLEANED_EXISTS=true
    
    # Check how many valid licenses were extracted (should be at least 8 from our setup)
    EXTRACTED_COUNT=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.vw_cleaned_listings WHERE REGEXP_LIKE(extracted_license, 'STR-[0-9]{4}-[0-9]{4}');" "system" | tr -d '[:space:]')
    EXTRACTED_COUNT=${EXTRACTED_COUNT:-0}
fi

# --- Check MV_STR_VIOLATIONS ---
MV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_mviews WHERE owner = 'HOUSING_ADMIN' AND mview_name = 'MV_STR_VIOLATIONS';" "system" | tr -d '[:space:]')
if [ "${MV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    MV_VIOLATIONS_EXISTS=true
    
    # Check for presence of each violation type in the concatenated reasons column
    UNLICENSED_DETECTED=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.mv_str_violations WHERE UPPER(violation_reasons) LIKE '%UNLICENSED%';" "system" | tr -d '[:space:]')
    UNLICENSED_DETECTED=${UNLICENSED_DETECTED:-0}
    
    # Expired/Revoked
    EXPIRED_DETECTED=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.mv_str_violations WHERE UPPER(violation_reasons) LIKE '%EXPIRED%' OR UPPER(violation_reasons) LIKE '%REVOKED%';" "system" | tr -d '[:space:]')
    EXPIRED_DETECTED=${EXPIRED_DETECTED:-0}
    
    DUPLICATE_DETECTED=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.mv_str_violations WHERE UPPER(violation_reasons) LIKE '%DUPLICATE%';" "system" | tr -d '[:space:]')
    DUPLICATE_DETECTED=${DUPLICATE_DETECTED:-0}
    
    COMMERCIAL_DETECTED=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.mv_str_violations WHERE UPPER(violation_reasons) LIKE '%COMMERCIAL%';" "system" | tr -d '[:space:]')
    COMMERCIAL_DETECTED=${COMMERCIAL_DETECTED:-0}
    
    # Over limit
    OVER_LIMIT_DETECTED=$(oracle_query_raw "SELECT COUNT(*) FROM housing_admin.mv_str_violations WHERE UPPER(violation_reasons) LIKE '%OVER_LIMIT%' OR UPPER(violation_reasons) LIKE '%OVER%RENT%';" "system" | tr -d '[:space:]')
    OVER_LIMIT_DETECTED=${OVER_LIMIT_DETECTED:-0}
fi

# --- Check CSV export ---
CSV_PATH="/home/ga/Documents/exports/illegal_str_targets.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null | tr -d '[:space:]')
    CSV_SIZE=${CSV_SIZE:-0}
fi

# --- Collect GUI evidence ---
GUI_EVIDENCE=$(collect_gui_evidence)

# Create JSON result
TEMP_JSON=$(mktemp /tmp/str_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "vw_cleaned_exists": $VW_CLEANED_EXISTS,
    "extracted_count": $EXTRACTED_COUNT,
    "mv_violations_exists": $MV_VIOLATIONS_EXISTS,
    "unlicensed_detected": $UNLICENSED_DETECTED,
    "expired_detected": $EXPIRED_DETECTED,
    "duplicate_detected": $DUPLICATE_DETECTED,
    "commercial_detected": $COMMERCIAL_DETECTED,
    "over_limit_detected": $OVER_LIMIT_DETECTED,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_EVIDENCE,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location securely
rm -f /tmp/str_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/str_result.json 2>/dev/null
chmod 666 /tmp/str_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/str_result.json"
cat /tmp/str_result.json
echo "=== Export complete ==="