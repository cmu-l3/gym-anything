#!/bin/bash
# pre_task hook for upload_document task.
# Puts the Quarterly_Report.pdf on the Desktop for the agent to upload,
# and opens Firefox to the Projects workspace.

echo "=== Setting up upload_document task ==="

source /workspace/scripts/task_utils.sh

wait_for_nuxeo 120

# Remove any existing 'Quarterly-Report' document (clean state)
CODE=$(curl -s -o /dev/null -w "%{http_code}" -u "$NUXEO_AUTH" \
    "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Quarterly-Report")
if [ "$CODE" = "200" ]; then
    curl -s -u "$NUXEO_AUTH" -X DELETE \
        "$NUXEO_URL/api/v1/path/default-domain/workspaces/Projects/Quarterly-Report" || true
    sleep 2
fi

# Place a real PDF on the Desktop for the agent to upload
mkdir -p /home/ga/Desktop
DESKTOP_PDF="/home/ga/Desktop/Quarterly_Report.pdf"
if [ -f "/workspace/data/quarterly_report.pdf" ]; then
    cp /workspace/data/quarterly_report.pdf "$DESKTOP_PDF"
    echo "Real PDF placed at: $DESKTOP_PDF ($(du -sh "$DESKTOP_PDF" | cut -f1))"
elif [ -f "/home/ga/nuxeo/data/Contract_Template.pdf" ]; then
    cp /home/ga/nuxeo/data/Contract_Template.pdf "$DESKTOP_PDF"
    echo "PDF placed at: $DESKTOP_PDF ($(du -sh "$DESKTOP_PDF" | cut -f1))"
else
    echo "WARNING: No real PDF found; using fallback"
    printf '%%PDF-1.4\n1 0 obj<</Type/Catalog/Pages 2 0 R>>endobj\n2 0 obj<</Type/Pages/Kids[3 0 R]/Count 1>>endobj\n3 0 obj<</Type/Page/MediaBox[0 0 595 842]/Parent 2 0 R>>endobj\nxref\n0 4\n0000000000 65535 f\n0000000009 00000 n\n0000000058 00000 n\n0000000115 00000 n\ntrailer<</Size 4/Root 1 0 R>>\nstartxref\n190\n%%%%EOF\n' > "$DESKTOP_PDF"
fi
chown ga:ga "$DESKTOP_PDF"

# Open Firefox, log in, navigate to Projects workspace
open_nuxeo_url "$NUXEO_URL/login.jsp" 8

sleep 3
PAGE_TITLE=$(DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    xdotool getactivewindow getwindowname 2>/dev/null || echo "")
if ! echo "$PAGE_TITLE" | grep -q " - Nuxeo Platform"; then
    nuxeo_login
fi

sleep 2
navigate_to "$NUXEO_UI/#!/browse/default-domain/workspaces/Projects"
sleep 4

echo "Task start state: Firefox is on the Projects workspace page."
echo "PDF file available at: $DESKTOP_PDF"
echo "Agent must upload the PDF and create a File document titled 'Quarterly Report'."
echo "=== upload_document task setup complete ==="
