#!/bin/bash
# Export script for ephemeral_container_distroless_debug task

echo "=== Exporting ephemeral_container_distroless_debug result ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Take final screenshot
take_screenshot /tmp/task_final.png 2>/dev/null || true

# ── Read Ground Truth & Initial State ─────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
GROUND_TRUTH=$(cat /tmp/ground_truth_signature.txt 2>/dev/null || echo "missing")
INITIAL_UID=$(cat /tmp/initial_pod_uid.txt 2>/dev/null || echo "missing")

# ── Fetch Current Pod State ───────────────────────────────────────────────────
CURRENT_UID=$(docker exec rancher kubectl get pod order-processor -n sales-prod -o jsonpath='{.metadata.uid}' 2>/dev/null || echo "not-found")

# Count ephemeral containers attached to the pod
EPHEMERAL_COUNT=$(docker exec rancher kubectl get pod order-processor -n sales-prod -o jsonpath='{range .spec.ephemeralContainers[*]}{.name}{"\n"}{end}' 2>/dev/null | grep -c "." || echo "0")

# ── Fetch the Secret ──────────────────────────────────────────────────────────
SECRET_JSON=$(docker exec rancher kubectl get secret fault-signature-hotfix -n sales-prod -o json 2>/dev/null || echo '{}')

# Extract and decode the signature key from the secret
EXTRACTED_SIGNATURE=$(echo "$SECRET_JSON" | python3 -c "
import json, sys, base64
try:
    data = json.load(sys.stdin)
    b64_val = data.get('data', {}).get('signature', '')
    if b64_val:
        print(base64.b64decode(b64_val).decode('utf-8').strip())
    else:
        print('none')
except Exception:
    print('error')
" 2>/dev/null || echo "error")

SECRET_EXISTS=$(echo "$SECRET_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if data.get('metadata', {}).get('name') == 'fault-signature-hotfix' else 'false')
" 2>/dev/null || echo "false")

HAS_SIGNATURE_KEY=$(echo "$SECRET_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('true' if 'signature' in data.get('data', {}) else 'false')
" 2>/dev/null || echo "false")

# ── Write result JSON ─────────────────────────────────────────────────────────
TEMP_JSON=$(mktemp /tmp/ephemeral_debug_result.XXXXXX.json)
cat > "$TEMP_JSON" <<EOF
{
    "task_start": $TASK_START,
    "ground_truth_signature": "$GROUND_TRUTH",
    "initial_pod_uid": "$INITIAL_UID",
    "current_pod_uid": "$CURRENT_UID",
    "ephemeral_container_count": $EPHEMERAL_COUNT,
    "secret_exists": $SECRET_EXISTS,
    "has_signature_key": $HAS_SIGNATURE_KEY,
    "extracted_signature": "$EXTRACTED_SIGNATURE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/ephemeral_debug_result.json 2>/dev/null || sudo rm -f /tmp/ephemeral_debug_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/ephemeral_debug_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/ephemeral_debug_result.json
chmod 666 /tmp/ephemeral_debug_result.json 2>/dev/null || sudo chmod 666 /tmp/ephemeral_debug_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON written to /tmp/ephemeral_debug_result.json"
cat /tmp/ephemeral_debug_result.json
echo ""
echo "=== Export Complete ==="