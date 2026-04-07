#!/bin/bash
echo "=== Setting up aviation_tool_calibration_certification task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Helper to get ID from API response safely
get_id() {
    echo "$1" | jq -r '.payload.id // .id // empty' 2>/dev/null
}

echo "  Setting up Custom Fields and Models..."

# 1. Create Category
CAT_ID=$(get_id "$(snipeit_api POST "categories" '{"name":"Precision Tools","category_type":"asset"}')")

# 2. Create Custom Fieldset
FS_ID=$(get_id "$(snipeit_api POST "fieldsets" '{"name":"Calibration Tracking"}')")

# 3. Create Custom Field
FIELD_ID=$(get_id "$(snipeit_api POST "fields" '{"name":"Next Calibration Date","element":"date","field_values":"","format":"date"}')")

# Associate field to fieldset
snipeit_api POST "fieldsets/${FS_ID}/fields" "{\"field_id\":${FIELD_ID},\"required\":0}" > /dev/null

# 4. Create Model
MODEL_ID=$(get_id "$(snipeit_api POST "models" "{\"name\":\"TechAngle Digital Torque Wrench\",\"category_id\":${CAT_ID},\"fieldset_id\":${FS_ID}}")")

# 5. Status Labels
SL_READY=$(snipeit_api GET "statuslabels" | jq -r '.rows[] | select(.name=="Ready to Deploy") | .id')
if [ -z "$SL_READY" ]; then
    SL_READY=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Ready to Deploy","type":"deployable","color":"#00FF00","show_in_nav":true}')")
fi

# Create "Out for Calibration" status
SL_CAL=$(get_id "$(snipeit_api POST "statuslabels" '{"name":"Out for Calibration","type":"undeployable","color":"#FF9800","show_in_nav":true}')")

echo "  Creating assets..."

# 6. Create Target Assets (Out for Calibration)
for i in 1 2 3 4; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-CAL-00$i\",\"name\":\"Torque Wrench 00$i\",\"model_id\":${MODEL_ID},\"status_id\":${SL_CAL},\"serial\":\"TW-2023-00$i\"}" > /dev/null
done

# 7. Create Decoy Assets (Already Ready to Deploy)
for i in 5 6; do
    snipeit_api POST "hardware" "{\"asset_tag\":\"ASSET-CAL-00$i\",\"name\":\"Torque Wrench 00$i\",\"model_id\":${MODEL_ID},\"status_id\":${SL_READY},\"serial\":\"TW-2023-00$i\",\"notes\":\"Calibrated last month\"}" > /dev/null
done

echo "  Generating PDF Certificates..."

# 8. Create valid dummy PDF files for upload
DOC_DIR="/home/ga/Documents/Calibration_Certs"
mkdir -p "$DOC_DIR"

create_dummy_pdf() {
  cat <<EOPDF > "$1"
%PDF-1.4
1 0 obj
<< /Type /Catalog /Pages 2 0 R >>
endobj
2 0 obj
<< /Type /Pages /Kids [3 0 R] /Count 1 >>
endobj
3 0 obj
<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 << /Type /Font /Subtype /Type1 /BaseFont /Helvetica >> >> >> /Contents 4 0 R >>
endobj
4 0 obj
<< /Length 58 >>
stream
BT
/F1 24 Tf
50 700 Td
($2) Tj
ET
endstream
endobj
xref
0 5
0000000000 65535 f 
0000000009 00000 n 
0000000058 00000 n 
0000000115 00000 n 
0000000289 00000 n 
trailer
<< /Size 5 /Root 1 0 R >>
startxref
396
%%EOF
EOPDF
}

for i in 1 2 3 4; do
    create_dummy_pdf "$DOC_DIR/Cert_CAL-00$i.pdf" "Calibration Certificate: ASSET-CAL-00$i"
done
chown -R ga:ga "$DOC_DIR"

# 9. Record task start time and baseline
date +%s > /tmp/task_start_time.txt
snipeit_db_query "SELECT COUNT(*) FROM action_logs WHERE action_type='uploaded'" > /tmp/initial_upload_count.txt

# 10. Ensure Firefox is ready
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/task_initial_state.png

echo "=== Setup complete ==="