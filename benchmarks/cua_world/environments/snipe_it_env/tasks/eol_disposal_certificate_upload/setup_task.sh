#!/bin/bash
echo "=== Setting up eol_disposal_certificate_upload task ==="

source /workspace/scripts/task_utils.sh

# 1. Generate the realistic Certificate of Destruction PDF
echo "  Generating Certificate of Destruction PDF..."
mkdir -p /home/ga/Documents
convert -size 800x1050 xc:white \
    -font DejaVu-Sans -pointsize 28 -fill black -draw "text 100,100 'CERTIFICATE OF DESTRUCTION'" \
    -pointsize 18 -draw "text 100,160 'Vendor: SecureEwaste Inc.'" \
    -draw "text 100,200 'Date: 2024-10-15'" \
    -draw "text 100,240 'Batch: Q3-2024'" \
    -draw "text 100,300 'Assets Destroyed:'" \
    -draw "text 120,340 '- HD-DISP-001'" \
    -draw "text 120,380 '- HD-DISP-002'" \
    -draw "text 120,420 '- HD-DISP-003'" \
    -draw "text 120,460 '- HD-DISP-004'" \
    -fill red -draw "text 100,560 'CONFIDENTIAL & COMPLIANCE VERIFIED'" \
    /home/ga/Documents/Certificate_of_Destruction_Q3.pdf

chown ga:ga /home/ga/Documents/Certificate_of_Destruction_Q3.pdf

# 2. Check/create "Pending Disposal" status label
PENDING_DISP_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Pending Disposal' LIMIT 1" | tr -d '[:space:]')
if [ -z "$PENDING_DISP_ID" ]; then
    echo "  Creating 'Pending Disposal' status label..."
    snipeit_api POST "statuslabels" '{"name":"Pending Disposal","type":"undeployable","color":"#FF0000","show_in_nav":true}'
    sleep 2
    PENDING_DISP_ID=$(snipeit_db_query "SELECT id FROM status_labels WHERE name='Pending Disposal' LIMIT 1" | tr -d '[:space:]')
fi
echo "  Pending Disposal Status ID: $PENDING_DISP_ID"

# 3. Create Hard Drive model/category if needed
CAT_HD_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Hard Drives' LIMIT 1" | tr -d '[:space:]')
if [ -z "$CAT_HD_ID" ]; then
    snipeit_api POST "categories" '{"name":"Hard Drives","category_type":"asset","eol":36}'
    sleep 2
    CAT_HD_ID=$(snipeit_db_query "SELECT id FROM categories WHERE name='Hard Drives' LIMIT 1" | tr -d '[:space:]')
fi

MDL_HD_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Seagate 2TB HDD' LIMIT 1" | tr -d '[:space:]')
if [ -z "$MDL_HD_ID" ]; then
    MFR_ID=$(snipeit_db_query "SELECT id FROM manufacturers LIMIT 1" | tr -d '[:space:]')
    snipeit_api POST "models" "{\"name\":\"Seagate 2TB HDD\",\"category_id\":$CAT_HD_ID,\"manufacturer_id\":$MFR_ID}"
    sleep 2
    MDL_HD_ID=$(snipeit_db_query "SELECT id FROM models WHERE name='Seagate 2TB HDD' LIMIT 1" | tr -d '[:space:]')
fi

# 4. Inject the 5 hard drives
echo "  Injecting hard drive assets..."
for i in {1..5}; do
    TAG="HD-DISP-00$i"
    # Delete if exists to ensure clean state
    if asset_exists_by_tag "$TAG"; then
        snipeit_db_query "DELETE FROM assets WHERE asset_tag='$TAG'"
    fi
    # Create asset
    snipeit_api POST "hardware" "{\"asset_tag\":\"$TAG\",\"name\":\"Destroyed HDD $i\",\"model_id\":$MDL_HD_ID,\"status_id\":$PENDING_DISP_ID,\"serial\":\"SN-SEAGATE-00$i\"}"
done
sleep 2

# Record initial timestamp and pending label ID
date +%s > /tmp/eol_task_start.txt
echo "$PENDING_DISP_ID" > /tmp/eol_pending_disp_id.txt

# Start Firefox and navigate to Hardware view
ensure_firefox_snipeit
sleep 2
navigate_firefox_to "http://localhost:8000/hardware"
sleep 3
take_screenshot /tmp/eol_disposal_initial.png

echo "=== eol_disposal_certificate_upload setup complete ==="