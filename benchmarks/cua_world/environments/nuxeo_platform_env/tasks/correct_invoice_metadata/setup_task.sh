#!/bin/bash
echo "=== Setting up correct_invoice_metadata task ==="

source /workspace/scripts/task_utils.sh

# 1. Wait for Nuxeo to be ready
wait_for_nuxeo 120

# 2. Generate Random Invoice Data
INVOICE_NUM="INV-$((1000 + RANDOM % 9000))"
# Select random vendor
VENDORS=("Acme Corp" "Globex Inc" "Soylent Corp" "Umbrella Corp" "Cyberdyne Systems")
RAND_IDX=$((RANDOM % ${#VENDORS[@]}))
VENDOR="${VENDORS[$RAND_IDX]}"
# Generate random amount
AMOUNT="\$$(shuf -i 100-5000 -n 1).$(shuf -i 10-99 -n 1)"

echo "Generated Ground Truth:"
echo "  Invoice #: $INVOICE_NUM"
echo "  Vendor:    $VENDOR"
echo "  Total:     $AMOUNT"

# Save ground truth for verification (hidden location)
mkdir -p /var/lib/nuxeo
cat > /var/lib/nuxeo/invoice_ground_truth.json <<EOF
{
  "invoice_number": "$INVOICE_NUM",
  "vendor": "$VENDOR",
  "amount": "$AMOUNT",
  "task_start_time": $(date +%s)
}
EOF
chmod 644 /var/lib/nuxeo/invoice_ground_truth.json

# 3. Create the Invoice Image
IMAGE_PATH="/tmp/invoice.png"
# Ensure imagemagick is installed (it is in env, but verify)
if ! command -v convert &> /dev/null; then
    apt-get update && apt-get install -y imagemagick
fi

convert -size 600x800 xc:white \
    -fill black -font DejaVu-Sans-Bold -pointsize 24 -draw "text 50,50 'INVOICE'" \
    -font DejaVu-Sans -pointsize 14 \
    -draw "text 50,100 'Invoice #: $INVOICE_NUM'" \
    -draw "text 50,130 'Date: $(date +%Y-%m-%d)'" \
    -draw "text 50,160 'Vendor: $VENDOR'" \
    -draw "line 50,200 550,200" \
    -draw "text 50,250 'Consulting Services'" \
    -draw "text 50,270 'Hours: 10'" \
    -draw "text 50,290 'Rate: $100/hr'" \
    -font DejaVu-Sans-Bold -pointsize 18 \
    -draw "text 350,600 'Total: $AMOUNT'" \
    "$IMAGE_PATH"

echo "Created invoice image at $IMAGE_PATH"

# 4. Clean up previous state (delete existing doc if any)
EXISTING_UID=$(nuxeo_api GET "/path/default-domain/workspaces/Projects/Scanned-Invoice" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))" 2>/dev/null)

if [ -n "$EXISTING_UID" ]; then
    echo "Removing existing document (uid=$EXISTING_UID)..."
    nuxeo_api DELETE "/id/$EXISTING_UID" > /dev/null
    sleep 2
fi

# 5. Create the Document with Placeholder Metadata
# First, get a batch ID for upload
BATCH_ID=$(curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('batchId',''))")

# Upload the file
FILE_SIZE=$(stat -c%s "$IMAGE_PATH")
curl -s -u "$NUXEO_AUTH" -X POST "$NUXEO_URL/api/v1/upload/$BATCH_ID/0" \
    -H "Content-Type: application/octet-stream" \
    -H "X-File-Name: scanned_invoice.png" \
    -H "X-File-Type: image/png" \
    -H "X-File-Size: $FILE_SIZE" \
    --data-binary @"$IMAGE_PATH" > /dev/null

# Create the document
PAYLOAD=$(cat <<EOFJSON
{
  "entity-type": "document",
  "type": "File",
  "name": "Scanned-Invoice",
  "properties": {
    "dc:title": "INV-0000-TEMP",
    "dc:source": "Unknown Vendor",
    "dc:description": "Automatic Import - Metadata Verification Required",
    "file:content": {
      "upload-batch": "$BATCH_ID",
      "upload-fileId": "0"
    }
  }
}
EOFJSON
)

echo "Creating document in Nuxeo..."
DOC_UID=$(nuxeo_api POST "/path/default-domain/workspaces/Projects/" "$PAYLOAD" | \
    python3 -c "import sys,json; print(json.load(sys.stdin).get('uid',''))")

echo "Document created with UID: $DOC_UID"
echo "$DOC_UID" > /tmp/task_doc_uid.txt

# 6. Prepare Browser
# Open Firefox, log in, navigate to the document
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
# Login if needed
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
# Navigate directly to the document
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects/Scanned-Invoice"
sleep 4

# Take initial screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="