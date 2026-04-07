#!/bin/bash
echo "=== Exporting Geological Drill Hole Compositing Results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Initialize verification flags
OVERLAPS_REMAINING=99
SUMMARY_VW_EXISTS=false
SUMMARY_H001_AU=0
INTERCEPTS_VW_EXISTS=false
MATCH_RECOGNIZE_USED=false
NUM_INTERCEPTS=0
INTERCEPTS_H002_LENGTH=0
LOCATIONS_VW_EXISTS=false
LOCATIONS_H002_Z=0
CSV_EXISTS=false
CSV_SIZE=0

# 1. Check for remaining overlaps
OVERLAPS_REMAINING=$(oracle_query_raw "
SELECT COUNT(*) FROM (
  SELECT hole_id, depth_from, depth_to, 
         LAG(depth_to) OVER (PARTITION BY hole_id ORDER BY depth_from) as prev_to 
  FROM geo_admin.core_assays
) WHERE depth_from < prev_to;" "system" | tr -d '[:space:]')
OVERLAPS_REMAINING=${OVERLAPS_REMAINING:-99}

# 2. Check HOLE_SUMMARY_VW
SUMMARY_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'GEO_ADMIN' AND view_name = 'HOLE_SUMMARY_VW';" "system" | tr -d '[:space:]')
if [ "${SUMMARY_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SUMMARY_VW_EXISTS=true
    
    # Check Math for H001: Original intervals had overlaps. After fixing:
    # 0-1.5 (0.1), 1.5-3.0 (0.2), 3.0-4.5 (0.5), 4.5-6.0 (0.6)
    # Sum length = 6.0
    # Sum (len*au) = (1.5*0.1) + (1.5*0.2) + (1.5*0.5) + (1.5*0.6) = 0.15 + 0.3 + 0.75 + 0.9 = 2.1
    # Weighted avg = 2.1 / 6.0 = 0.35
    SUMMARY_H001_AU=$(oracle_query_raw "SELECT ROUND(weighted_avg_au, 3) FROM geo_admin.hole_summary_vw WHERE hole_id = 'H001';" "system" | tr -d '[:space:]')
    SUMMARY_H001_AU=${SUMMARY_H001_AU:-0}
fi

# 3. Check SIGNIFICANT_INTERCEPTS_VW
INTERCEPTS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'GEO_ADMIN' AND view_name = 'SIGNIFICANT_INTERCEPTS_VW';" "system" | tr -d '[:space:]')
if [ "${INTERCEPTS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    INTERCEPTS_VW_EXISTS=true
    
    # Verify MATCH_RECOGNIZE is used in the view definition
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner = 'GEO_ADMIN' AND view_name = 'SIGNIFICANT_INTERCEPTS_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "MATCH_RECOGNIZE" 2>/dev/null; then
        MATCH_RECOGNIZE_USED=true
    fi
    
    # Check count of valid intercepts. Should be exactly 1 (H002, 10 to 14.5).
    NUM_INTERCEPTS=$(oracle_query_raw "SELECT COUNT(*) FROM geo_admin.significant_intercepts_vw;" "system" | tr -d '[:space:]')
    NUM_INTERCEPTS=${NUM_INTERCEPTS:-0}
    
    # Check length of H002 intercept
    INTERCEPTS_H002_LENGTH=$(oracle_query_raw "SELECT ROUND(MAX(intercept_length), 2) FROM geo_admin.significant_intercepts_vw WHERE hole_id = 'H002';" "system" | tr -d '[:space:]')
    INTERCEPTS_H002_LENGTH=${INTERCEPTS_H002_LENGTH:-0}
fi

# 4. Check INTERCEPT_3D_LOCATIONS_VW
LOCATIONS_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner = 'GEO_ADMIN' AND view_name = 'INTERCEPT_3D_LOCATIONS_VW';" "system" | tr -d '[:space:]')
if [ "${LOCATIONS_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    LOCATIONS_VW_EXISTS=true
    
    # Check 3D Z-coordinate calculation
    # H002: elevation = 410. Intercept starts at 10, length = 4.5.
    # Center Z = 410 - (10 + 4.5/2) = 410 - 12.25 = 397.75
    LOCATIONS_H002_Z=$(oracle_query_raw "SELECT ROUND(center_z, 2) FROM geo_admin.intercept_3d_locations_vw WHERE hole_id = 'H002';" "system" | tr -d '[:space:]')
    LOCATIONS_H002_Z=${LOCATIONS_H002_Z:-0}
fi

# 5. Check CSV export
CSV_PATH="/home/ga/Documents/exports/significant_intercepts.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null || echo "0")
fi

# 6. Gather GUI usage evidence
GUI_EVIDENCE=$(collect_gui_evidence)

# 7. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "overlaps_remaining": $OVERLAPS_REMAINING,
    "summary_vw_exists": $SUMMARY_VW_EXISTS,
    "summary_h001_au": "$SUMMARY_H001_AU",
    "intercepts_vw_exists": $INTERCEPTS_VW_EXISTS,
    "match_recognize_used": $MATCH_RECOGNIZE_USED,
    "num_intercepts": $NUM_INTERCEPTS,
    "intercepts_h002_length": "$INTERCEPTS_H002_LENGTH",
    "locations_vw_exists": $LOCATIONS_VW_EXISTS,
    "locations_h002_z": "$LOCATIONS_H002_Z",
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    ${GUI_EVIDENCE}
}
EOF

rm -f /tmp/geo_task_result.json 2>/dev/null || sudo rm -f /tmp/geo_task_result.json
cp "$TEMP_JSON" /tmp/geo_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/geo_task_result.json
chmod 666 /tmp/geo_task_result.json 2>/dev/null || sudo chmod 666 /tmp/geo_task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/geo_task_result.json"
cat /tmp/geo_task_result.json

echo "=== Export Complete ==="