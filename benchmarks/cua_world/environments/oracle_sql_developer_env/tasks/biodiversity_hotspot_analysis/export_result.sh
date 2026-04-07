#!/bin/bash
# Export results for Biodiversity Hotspot Analysis task
echo "=== Exporting Biodiversity Hotspot Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_end_screenshot.png ga

# -----------------------------------------------------------------------------
# Pull the CSV from the oracle container's EXPORT_DIR to the host expected path
# -----------------------------------------------------------------------------
# Agent writes to EXPORT_DIR which maps to /opt/oracle/exports inside the container
sudo docker cp oracle-xe:/opt/oracle/exports/conservation_gap_report.csv /home/ga/Documents/exports/conservation_gap_report.csv 2>/dev/null || true

# Initialize metrics
HAVERSINE_EXISTS=false
HAVERSINE_SF_LA_KM=0
SHANNON_EXISTS=false
SHANNON_SITE1=0
SIMPSON_EXISTS=false
SIMPSON_SITE1=0
TAXONOMIC_VW_EXISTS=false
CONNECT_BY_USED=false
PROXIMITY_VW_EXISTS=false
SEASONAL_VW_EXISTS=false
WINDOW_FUNC_USED=false
GAP_VW_EXISTS=false
PROC_EXISTS=false
CSV_EXISTS=false
CSV_SIZE=0

# --- Check 1: Haversine Function ---
HAV_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='WILDLIFE_BIO' AND object_name='FUNC_HAVERSINE_KM' AND object_type='FUNCTION';" "system" | tr -d '[:space:]')
if [ "${HAV_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    HAVERSINE_EXISTS=true
    # Test accuracy: SF to LA (approx 559 km)
    HAVERSINE_SF_LA_KM=$(oracle_query_raw "SELECT ROUND(wildlife_bio.func_haversine_km(37.7749, -122.4194, 34.0522, -118.2437), 1) FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ ! "$HAVERSINE_SF_LA_KM" =~ ^[0-9.]+$ ]]; then HAVERSINE_SF_LA_KM=0; fi
fi

# --- Check 2: Shannon & Simpson Functions ---
SHAN_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='WILDLIFE_BIO' AND object_name='FUNC_SHANNON_INDEX' AND object_type='FUNCTION';" "system" | tr -d '[:space:]')
if [ "${SHAN_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SHANNON_EXISTS=true
    # Test value on Site 2 (Hotspot, highly diverse)
    SHANNON_SITE1=$(oracle_query_raw "SELECT ROUND(wildlife_bio.func_shannon_index(2), 3) FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ ! "$SHANNON_SITE1" =~ ^-?[0-9.]+$ ]]; then SHANNON_SITE1=-1; fi
fi

SIMP_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_objects WHERE owner='WILDLIFE_BIO' AND object_name='FUNC_SIMPSON_INDEX' AND object_type='FUNCTION';" "system" | tr -d '[:space:]')
if [ "${SIMP_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SIMPSON_EXISTS=true
    SIMPSON_SITE1=$(oracle_query_raw "SELECT ROUND(wildlife_bio.func_simpson_index(2), 3) FROM DUAL;" "system" 2>/dev/null | tr -d '[:space:]')
    if [[ ! "$SIMPSON_SITE1" =~ ^-?[0-9.]+$ ]]; then SIMPSON_SITE1=-1; fi
fi

# --- Check 3: Taxonomic Tree View ---
TAX_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='TAXONOMIC_TREE_VW';" "system" | tr -d '[:space:]')
if [ "${TAX_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    TAXONOMIC_VW_EXISTS=true
    VW_TEXT=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='TAXONOMIC_TREE_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT" | grep -qiE "CONNECT\s*BY|SYS_CONNECT_BY_PATH" 2>/dev/null; then
        CONNECT_BY_USED=true
    fi
fi

# --- Check 4: Protected Area Proximity View ---
PROX_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='SPECIES_NEAR_PROTECTED_VW';" "system" | tr -d '[:space:]')
if [ "${PROX_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROXIMITY_VW_EXISTS=true
fi

# --- Check 5: Seasonal Phenology View ---
SEAS_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='SEASONAL_PATTERNS_VW';" "system" | tr -d '[:space:]')
if [ "${SEAS_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    SEASONAL_VW_EXISTS=true
    VW_TEXT_S=$(oracle_query_raw "SELECT text FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='SEASONAL_PATTERNS_VW';" "system" 2>/dev/null)
    if echo "$VW_TEXT_S" | grep -qiE "OVER\s*\(|LAG\s*\(|LEAD\s*\(|AVG.*OVER" 2>/dev/null; then
        WINDOW_FUNC_USED=true
    fi
fi

# --- Check 6: Conservation GAP View ---
GAP_VW_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_views WHERE owner='WILDLIFE_BIO' AND view_name='CONSERVATION_GAP_VW';" "system" | tr -d '[:space:]')
if [ "${GAP_VW_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    GAP_VW_EXISTS=true
fi

# --- Check 7: Export Procedure & CSV ---
PROC_CHECK=$(oracle_query_raw "SELECT COUNT(*) FROM all_procedures WHERE owner='WILDLIFE_BIO' AND object_name='PROC_EXPORT_GAP_REPORT';" "system" | tr -d '[:space:]')
if [ "${PROC_CHECK:-0}" -gt 0 ] 2>/dev/null; then
    PROC_EXISTS=true
fi

CSV_PATH="/home/ga/Documents/exports/conservation_gap_report.csv"
if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS=true
    CSV_SIZE=$(wc -c < "$CSV_PATH" 2>/dev/null || echo "0")
fi

# Collect GUI usage evidence
GUI_JSON=$(collect_gui_evidence)

# Export everything to JSON result file
TEMP_JSON=$(mktemp /tmp/biodiversity_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "haversine_exists": $HAVERSINE_EXISTS,
    "haversine_sf_la_km": $HAVERSINE_SF_LA_KM,
    "shannon_exists": $SHANNON_EXISTS,
    "shannon_site1": $SHANNON_SITE1,
    "simpson_exists": $SIMPSON_EXISTS,
    "simpson_site1": $SIMPSON_SITE1,
    "taxonomic_vw_exists": $TAXONOMIC_VW_EXISTS,
    "connect_by_used": $CONNECT_BY_USED,
    "proximity_vw_exists": $PROXIMITY_VW_EXISTS,
    "seasonal_vw_exists": $SEASONAL_VW_EXISTS,
    "window_func_used": $WINDOW_FUNC_USED,
    "gap_vw_exists": $GAP_VW_EXISTS,
    "proc_exists": $PROC_EXISTS,
    "csv_exists": $CSV_EXISTS,
    "csv_size": $CSV_SIZE,
    $GUI_JSON,
    "export_timestamp": "$(date +%s)"
}
EOF

# Move to standard accessible location
rm -f /tmp/biodiversity_result.json 2>/dev/null || sudo rm -f /tmp/biodiversity_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/biodiversity_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/biodiversity_result.json
chmod 666 /tmp/biodiversity_result.json 2>/dev/null || sudo chmod 666 /tmp/biodiversity_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/biodiversity_result.json"
cat /tmp/biodiversity_result.json
echo "=== Export Complete ==="