#!/bin/bash
echo "=== Setting up create_folder_structure task ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/task_start_time.txt

# ── 1. Verify documents exist in Reports folder ──────────────────────────────
echo "Verifying source documents exist in Reports folder..."

DOCS_DIR="/home/ga/openkm_data"

for doc in "NIST_Cybersecurity_Framework.pdf" "OWASP_Testing_Guide_Summary.pdf"; do
    DOC_PATH="/okm:root/Reports/${doc}"
    if openkm_doc_exists "$DOC_PATH"; then
        echo "  Found: $DOC_PATH"
    else
        echo "  WARNING: $DOC_PATH not found, re-uploading..."
        if [ -f "$DOCS_DIR/$doc" ]; then
            curl -s -o /dev/null \
                -u "${OPENKM_USER}:${OPENKM_PASS}" \
                -H "Accept: application/json" \
                -X POST \
                -F "docPath=${DOC_PATH}" \
                -F "content=@${DOCS_DIR}/${doc}" \
                "${OPENKM_API}/document/createSimple" 2>/dev/null
            echo "  Re-uploaded: $doc"
        fi
    fi
done

# ── 2. Remove Security folder if it already exists (ensure clean state) ──────
curl -s -o /dev/null \
    -u "${OPENKM_USER}:${OPENKM_PASS}" \
    -H "Accept: application/json" \
    -X DELETE \
    "${OPENKM_API}/folder/delete?fldId=/okm:root/Security" 2>/dev/null || true

# Also purge from trash
curl -s -o /dev/null \
    -u "${OPENKM_USER}:${OPENKM_PASS}" \
    -H "Accept: application/json" \
    -X PUT \
    "${OPENKM_API}/folder/purge?fldId=/okm:trash/${OPENKM_USER}/Security" 2>/dev/null || true

echo "Security folder cleaned (if existed)"

# ── 3. Launch Firefox and log in to OpenKM ────────────────────────────────────
launch_firefox "${OPENKM_URL}/login.jsp"
auto_login_openkm "${OPENKM_URL}/frontend/index.jsp"
sleep 5

take_screenshot /tmp/task_initial.png

echo "=== create_folder_structure task setup complete ==="
echo "Create: /okm:root/Security/Policies and /okm:root/Security/Audits"
echo "Move: NIST_Cybersecurity_Framework.pdf -> Security/Policies"
echo "Move: OWASP_Testing_Guide_Summary.pdf -> Security/Audits"
