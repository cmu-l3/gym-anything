#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Setting up task: transfer_misfiled_document ==="

# 1. Generate unique confidential document
DOC_PATH="/tmp/medical_evaluation_confidential.pdf"
# Create a PDF with unique content (timestamp) to ensure hash verification works
# using convert (ImageMagick) which is installed in the env
convert -size 600x800 xc:white -font DejaVu-Sans -pointsize 24 \
    -fill black \
    -draw "text 50,50 'CONFIDENTIAL MEDICAL EVALUATION'" \
    -draw "text 50,100 'Patient: John Smith'" \
    -draw "text 50,150 'DOB: 1980-05-12'" \
    -draw "text 50,200 'Generated: $(date)'" \
    "$DOC_PATH"

ORIGINAL_HASH=$(md5sum "$DOC_PATH" | awk '{print $1}')
echo "$ORIGINAL_HASH" > /tmp/original_doc_hash.txt
echo "Generated document with hash: $ORIGINAL_HASH"

# 2. Ensure ArkCase is ready
ensure_portforward
wait_for_arkcase

# 3. Create Case A (The "Wrong" Case)
echo "Creating Source Case (Wrong)..."
# Create complaint returns JSON
CASE_A_RESP=$(create_foia_case "Parking Violation - Smith" "Dispute regarding ticket #998877 at 4th St." "Low")
# Extract ID using python (jq might be available but python is safer fallback in some minimal envs, though jq is installed here)
CASE_A_ID=$(echo "$CASE_A_RESP" | jq -r '.id // .complaintId // empty')
CASE_A_NUM=$(echo "$CASE_A_RESP" | jq -r '.caseNumber // empty')

if [ -z "$CASE_A_ID" ]; then
    echo "ERROR: Failed to create source case. Response: $CASE_A_RESP"
    exit 1
fi
echo "Created Source Case: $CASE_A_NUM ($CASE_A_ID)"

# 4. Create Case B (The "Right" Case)
echo "Creating Target Case (Right)..."
CASE_B_RESP=$(create_foia_case "Personal Injury - Smith" "Claim for damages related to construction site accident on 5th Ave." "High")
CASE_B_ID=$(echo "$CASE_B_RESP" | jq -r '.id // .complaintId // empty')
CASE_B_NUM=$(echo "$CASE_B_RESP" | jq -r '.caseNumber // empty')

if [ -z "$CASE_B_ID" ]; then
    echo "ERROR: Failed to create target case. Response: $CASE_B_RESP"
    exit 1
fi
echo "Created Target Case: $CASE_B_NUM ($CASE_B_ID)"

# Save IDs for export script
cat > /tmp/task_config.json <<EOF
{
  "source_case_id": "$CASE_A_ID",
  "source_case_num": "$CASE_A_NUM",
  "target_case_id": "$CASE_B_ID",
  "target_case_num": "$CASE_B_NUM",
  "original_hash": "$ORIGINAL_HASH",
  "filename": "medical_evaluation_confidential.pdf"
}
EOF

# 5. Upload Document to Case A (Simulating the mistake)
echo "Uploading document to Source Case A..."
# Using curl with multipart/form-data for ArkCase document upload
# We use the creds from task_utils.sh
UPLOAD_RESP=$(curl -sk -X POST \
    -u "${ARKCASE_ADMIN}:${ARKCASE_PASS}" \
    -H "Accept: application/json" \
    -F "file=@$DOC_PATH" \
    -F "title=Medical Evaluation" \
    -F "docType=Medical" \
    "${ARKCASE_URL}/api/v1/plugin/complaint/${CASE_A_ID}/document")

# 6. Prepare Browser
# Launch Firefox and login
ensure_firefox_on_arkcase "${ARKCASE_URL}/home.html"
auto_login_arkcase "${ARKCASE_URL}/home.html"

# 7. Initial Screenshot
take_screenshot /tmp/task_initial.png

# Record start time
date +%s > /tmp/task_start_time.txt

echo "=== Task Setup Complete ==="