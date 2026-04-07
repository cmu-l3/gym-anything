#!/bin/bash
echo "=== Setting up upload_and_tag_document task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_time.txt
mkdir -p /home/ga/Documents /home/ga/Downloads

# ── 1. Prepare the real NIST SP 800-53 document for upload ────────────────────
# The actual NIST SP 800-53 Rev 5 was downloaded during install
NIST_SP_SOURCE="/home/ga/openkm_data/NIST_SP_800-53_Security_Controls.pdf"
UPLOAD_FILE="/home/ga/Documents/NIST_SP_800-53_Security_Controls.pdf"

if [ -f "$NIST_SP_SOURCE" ] && [ -s "$NIST_SP_SOURCE" ]; then
    cp "$NIST_SP_SOURCE" "$UPLOAD_FILE"
    echo "Prepared upload file from pre-downloaded NIST SP 800-53: $UPLOAD_FILE"
else
    # Fallback: download the actual NIST SP 800-53 Rev 5
    echo "Pre-downloaded NIST SP 800-53 not found, downloading..."
    wget -q --timeout=60 -O "$UPLOAD_FILE" \
        "https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-53r5.pdf" 2>/dev/null || {
        echo "ERROR: Could not download NIST SP 800-53"
        exit 1
    }
fi

chown ga:ga "$UPLOAD_FILE"
ls -la "$UPLOAD_FILE"

# ── 2. Ensure the Compliance folder exists (but has no copy of this doc) ──────
# Folder was created in setup but verify
curl -s -o /dev/null \
    -u "${OPENKM_USER}:${OPENKM_PASS}" \
    -H "Accept: application/json" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "/okm:root/Compliance" \
    "${OPENKM_API}/folder/createSimple" 2>/dev/null || true

# Remove the document from Compliance if it already exists (clean state)
curl -s -o /dev/null \
    -u "${OPENKM_USER}:${OPENKM_PASS}" \
    -X DELETE \
    "${OPENKM_API}/document/delete?docId=/okm:root/Compliance/NIST_SP_800-53_Security_Controls.pdf" 2>/dev/null || true

# ── 3. Launch Firefox and log in to OpenKM ────────────────────────────────────
launch_firefox "${OPENKM_URL}/login.jsp"
auto_login_openkm "${OPENKM_URL}/frontend/index.jsp"
sleep 5

take_screenshot /tmp/task_initial.png

echo "=== upload_and_tag_document task setup complete ==="
echo "Upload file: $UPLOAD_FILE"
echo "Target: /okm:root/Compliance/"
