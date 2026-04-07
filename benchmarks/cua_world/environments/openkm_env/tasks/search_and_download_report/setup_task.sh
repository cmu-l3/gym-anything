#!/bin/bash
echo "=== Setting up search_and_download_report task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_time.txt
mkdir -p /home/ga/Downloads /home/ga/Documents

# ── 1. Verify the target document exists in OpenKM ───────────────────────────
echo "Verifying EPA report exists in OpenKM..."
DOC_PATH="/okm:root/Reports/EPA_Environmental_Justice_Report.pdf"

if openkm_doc_exists "$DOC_PATH"; then
    echo "Target document exists in OpenKM: $DOC_PATH"
else
    echo "WARNING: Target document not found, attempting re-upload..."
    DOCS_DIR="/home/ga/openkm_data"
    if [ -f "$DOCS_DIR/EPA_Environmental_Justice_Report.pdf" ]; then
        curl -s -o /dev/null \
            -u "${OPENKM_USER}:${OPENKM_PASS}" \
            -H "Accept: application/json" \
            -X POST \
            -F "docPath=/okm:root/Reports/EPA_Environmental_Justice_Report.pdf" \
            -F "content=@${DOCS_DIR}/EPA_Environmental_Justice_Report.pdf" \
            "${OPENKM_API}/document/createSimple" 2>/dev/null
        echo "Re-uploaded EPA report"
    fi
fi

# ── 2. Clear Downloads directory to ensure clean state ────────────────────────
rm -f /home/ga/Downloads/EPA_Environmental_Justice_Report.pdf 2>/dev/null || true
rm -f /home/ga/Downloads/EPA_Environmental_Justice_Report*.pdf 2>/dev/null || true
echo "Downloads directory cleared of target file"

# ── 3. Launch Firefox and log in to OpenKM ────────────────────────────────────
launch_firefox "${OPENKM_URL}/login.jsp"
auto_login_openkm "${OPENKM_URL}/frontend/index.jsp"
sleep 5

take_screenshot /tmp/task_initial.png

echo "=== search_and_download_report task setup complete ==="
echo "Search for: EPA_Environmental_Justice_Report"
echo "Download to: ~/Downloads/"
