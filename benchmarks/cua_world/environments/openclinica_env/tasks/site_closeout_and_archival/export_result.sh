#!/bin/bash
echo "=== Exporting site_closeout_and_archival result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# 1. Check Site Status in DB
SITE_DATA=$(oc_query "SELECT status_id FROM study WHERE unique_identifier = 'CV-BHI-001' LIMIT 1" 2>/dev/null)
SITE_STATUS=${SITE_DATA:-1}
echo "Site CV-BHI-001 status_id: $SITE_STATUS"

# 2. Check Subject 1 Casebook
PDF1="/home/ga/Documents/CV-BHI-101_Casebook.pdf"
PDF1_EXISTS="false"
PDF1_SIZE=0
PDF1_NEW="false"
PDF1_VALID="false"

if [ -f "$PDF1" ]; then
    PDF1_EXISTS="true"
    PDF1_SIZE=$(stat -c%s "$PDF1" 2>/dev/null || echo "0")
    PDF1_MTIME=$(stat -c%Y "$PDF1" 2>/dev/null || echo "0")
    
    if [ "$PDF1_MTIME" -gt "$TASK_START" ]; then
        PDF1_NEW="true"
    fi
    
    # Try pdftotext, fallback to strings
    if pdftotext "$PDF1" - 2>/dev/null | grep -qi "CV-BHI-101"; then
        PDF1_VALID="true"
    elif strings "$PDF1" | grep -qi "CV-BHI-101"; then
        PDF1_VALID="true"
    fi
fi
echo "PDF1 exists: $PDF1_EXISTS, valid: $PDF1_VALID, size: $PDF1_SIZE"

# 3. Check Subject 2 Casebook
PDF2="/home/ga/Documents/CV-BHI-102_Casebook.pdf"
PDF2_EXISTS="false"
PDF2_SIZE=0
PDF2_NEW="false"
PDF2_VALID="false"

if [ -f "$PDF2" ]; then
    PDF2_EXISTS="true"
    PDF2_SIZE=$(stat -c%s "$PDF2" 2>/dev/null || echo "0")
    PDF2_MTIME=$(stat -c%Y "$PDF2" 2>/dev/null || echo "0")
    
    if [ "$PDF2_MTIME" -gt "$TASK_START" ]; then
        PDF2_NEW="true"
    fi
    
    if pdftotext "$PDF2" - 2>/dev/null | grep -qi "CV-BHI-102"; then
        PDF2_VALID="true"
    elif strings "$PDF2" | grep -qi "CV-BHI-102"; then
        PDF2_VALID="true"
    fi
fi
echo "PDF2 exists: $PDF2_EXISTS, valid: $PDF2_VALID, size: $PDF2_SIZE"

# 4. Check CDISC ODM XML
XML="/home/ga/Documents/BHI_Site_Data.xml"
XML_EXISTS="false"
XML_SIZE=0
XML_NEW="false"
XML_VALID="false"

if [ -f "$XML" ]; then
    XML_EXISTS="true"
    XML_SIZE=$(stat -c%s "$XML" 2>/dev/null || echo "0")
    XML_MTIME=$(stat -c%Y "$XML" 2>/dev/null || echo "0")
    
    if [ "$XML_MTIME" -gt "$TASK_START" ]; then
        XML_NEW="true"
    fi
    
    # Simple validation for CDISC XML
    if grep -qi "ODM\|ClinicalData" "$XML" && grep -qi "CV-BHI" "$XML"; then
        XML_VALID="true"
    fi
fi
echo "XML exists: $XML_EXISTS, valid: $XML_VALID, size: $XML_SIZE"

# 5. Check Audit logs
AUDIT_LOG_COUNT=$(get_recent_audit_count 60)
AUDIT_BASELINE_COUNT=$(cat /tmp/audit_baseline_count 2>/dev/null || echo "0")
NONCE=$(cat /tmp/result_nonce 2>/dev/null || echo "")

# Write JSON result
TEMP_JSON=$(mktemp /tmp/site_closeout_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "site_status_id": $SITE_STATUS,
    "pdf1_exists": $PDF1_EXISTS,
    "pdf1_size": $PDF1_SIZE,
    "pdf1_new": $PDF1_NEW,
    "pdf1_valid": $PDF1_VALID,
    "pdf2_exists": $PDF2_EXISTS,
    "pdf2_size": $PDF2_SIZE,
    "pdf2_new": $PDF2_NEW,
    "pdf2_valid": $PDF2_VALID,
    "xml_exists": $XML_EXISTS,
    "xml_size": $XML_SIZE,
    "xml_new": $XML_NEW,
    "xml_valid": $XML_VALID,
    "audit_log_count": $AUDIT_LOG_COUNT,
    "audit_baseline_count": $AUDIT_BASELINE_COUNT,
    "result_nonce": "$NONCE"
}
EOF

# Ensure safe file operations
rm -f /tmp/site_closeout_result.json 2>/dev/null || sudo rm -f /tmp/site_closeout_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/site_closeout_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/site_closeout_result.json
chmod 666 /tmp/site_closeout_result.json 2>/dev/null || sudo chmod 666 /tmp/site_closeout_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
cat /tmp/site_closeout_result.json