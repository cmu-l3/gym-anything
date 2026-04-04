#!/bin/bash
echo "=== Exporting reverse_patient_payment results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Configuration
PAYMENT_ID="payment_p1_seeded_123"
PATIENT_ID="patient_p1_P00555"

# 1. Check if Payment still exists
# curl returns 404 if deleted (or _deleted: true if we check revs, but 404 is standard for direct GET)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PAYMENT_ID}")

PAYMENT_EXISTS="true"
if [ "$HTTP_CODE" = "404" ]; then
    PAYMENT_EXISTS="false"
fi

# 2. Check if Patient still exists (Safety Check)
PATIENT_HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${HR_COUCH_URL}/${HR_COUCH_MAIN_DB}/${PATIENT_ID}")
PATIENT_EXISTS="false"
if [ "$PATIENT_HTTP_CODE" = "200" ]; then
    PATIENT_EXISTS="true"
fi

# 3. Create JSON result
cat > /tmp/task_result.json << EOF
{
  "payment_id": "$PAYMENT_ID",
  "payment_exists": $PAYMENT_EXISTS,
  "patient_id": "$PATIENT_ID",
  "patient_exists": $PATIENT_EXISTS,
  "timestamp": "$(date -Iseconds)"
}
EOF

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json